when not compileOption("threads"):
  {.error: "threadtools_vstream_runner requires --threads:on".}

import std/[monotimes, strformat, times]

import threadtools

import ./detector
import ../lowlevel
import ../bindings/[c_api, types]
import ../internal/[error, helper]

# ==============================================================================
# Public types
# ==============================================================================

type
  ThreadtoolsVStreamRunnerConfig* = object
    ## Configuration for the threadtools-based vstream path.
    ##
    ## submit() performs the input vstream write synchronously on the caller
    ## thread.  The dedicated read worker receives a small read request through a
    ## ThreadQueue, performs the blocking output vstream read, and sends the
    ## completion metadata back through another ThreadQueue.
    slotCount*: int
    inputQueueSize*: int
    resultQueueSize*: int

  ThreadtoolsVStreamResult* = object
    ## Completed output slot metadata.
    ##
    ## The output buffer remains owned by ThreadtoolsVStreamRunner.  The caller
    ## may read outputPtr until releaseResult() is called for this slot.
    slotIndex*: int
    outputPtr*: pointer
    outputSize*: int
    writeUs*: int64
    readUs*: int64

# ==============================================================================
# Private worker types
# ==============================================================================

type
  OutputSlot = object
    output: pointer

  ReadRequest = object
    slotIndex: int
    writeUs: int64

  DoneResult = object
    slotIndex: int
    status: hailo_status
    writeUs: int64
    readUs: int64

  ThreadtoolsVStreamState = object
    outputRaw: hailo_output_vstream
    outputSize: int
    slots: ptr UncheckedArray[OutputSlot]
    slotCount: int
    readReqQ: ThreadQueue[ReadRequest]
    doneQ: ThreadQueue[DoneResult]

  ThreadtoolsVStreamRunner* = ref object
    ## Generic vstream runner with a dedicated output read worker.
    ##
    ## This is model-output agnostic.  Higher-level code is responsible for
    ## parsing output bytes.
    ##
    ## The source Detector must stay alive and activated until close() returns.
    detector: Detector
    state: ThreadtoolsVStreamState
    readThread: Thread[ptr ThreadtoolsVStreamState]
    freeSlots: seq[int]
    config: ThreadtoolsVStreamRunnerConfig
    running: bool

# ==============================================================================
# Small helpers
# ==============================================================================

proc elapsedUs(started: MonoTime): int64 {.inline.} =
  result = inMicroseconds(getMonoTime() - started)

proc statusResult(status: hailo_status; where: string): HE[void] =
  if status != HAILO_SUCCESS:
    return makeError(status, &"{where}: {status}").err

  result = okVoid()

proc threadtoolsError(code: ErrorCode; where: string): HailoError =
  let status = case code
    of ErrorCode.Full:
      HAILO_QUEUE_IS_FULL
    of ErrorCode.Empty:
      HAILO_NOT_AVAILABLE
    of ErrorCode.Closed, ErrorCode.Cancelled:
      HAILO_INVALID_OPERATION
    of ErrorCode.Unsupported:
      HAILO_NOT_SUPPORTED
    else:
      HAILO_INVALID_OPERATION

  result = makeError(status, &"{where}: threadtools error: {code}")

proc freeOutputSlots(state: var ThreadtoolsVStreamState) =
  if state.slots.isNil:
    return

  for i in 0 ..< state.slotCount:
    if not state.slots[i].output.isNil:
      deallocShared(state.slots[i].output)
      state.slots[i].output = nil

  deallocShared(state.slots)
  state.slots = nil
  state.slotCount = 0

proc closeQueues(state: var ThreadtoolsVStreamState) =
  if not state.readReqQ.isNil:
    state.readReqQ.close()

  if not state.doneQ.isNil:
    state.doneQ.close()

# ==============================================================================
# Read worker
# ==============================================================================

proc readMain(state: ptr ThreadtoolsVStreamState) {.thread.} =
  while true:
    var reqRes = state.readReqQ.receiveResult()

    if reqRes.isErr:
      break

    var req = reqRes.take()

    if req.slotIndex < 0:
      break

    var done = DoneResult(
      slotIndex: req.slotIndex,
      status: HAILO_SUCCESS,
      writeUs: req.writeUs,
      readUs: 0
    )

    if req.slotIndex >= state.slotCount:
      done.status = HAILO_INVALID_ARGUMENT
      discard state.doneQ.sendMove(done)
      continue

    let slot = state.slots[req.slotIndex]
    let started = getMonoTime()
    done.status = hailo_vstream_read_raw_buffer(
      state.outputRaw,
      slot.output,
      csize_t(state.outputSize)
    )
    done.readUs = elapsedUs(started)

    discard state.doneQ.sendMove(done)

# ==============================================================================
# Public configuration
# ==============================================================================

proc defaultThreadtoolsVStreamRunnerConfig*(): ThreadtoolsVStreamRunnerConfig =
  result = ThreadtoolsVStreamRunnerConfig(
    slotCount: 2,
    inputQueueSize: 2,
    resultQueueSize: 2
  )

proc validateConfig(config: ThreadtoolsVStreamRunnerConfig): HE[void] =
  if config.slotCount <= 0:
    return makeError(HAILO_INVALID_ARGUMENT, "slotCount must be positive").err

  if config.inputQueueSize <= 0:
    return makeError(HAILO_INVALID_ARGUMENT, "inputQueueSize must be positive").err

  if config.resultQueueSize <= 0:
    return makeError(HAILO_INVALID_ARGUMENT, "resultQueueSize must be positive").err

  if config.inputQueueSize < config.slotCount:
    return makeError(
      HAILO_INVALID_ARGUMENT,
      &"inputQueueSize must be >= slotCount: inputQueueSize={config.inputQueueSize} slotCount={config.slotCount}"
    ).err

  if config.resultQueueSize < config.slotCount:
    return makeError(
      HAILO_INVALID_ARGUMENT,
      &"resultQueueSize must be >= slotCount: resultQueueSize={config.resultQueueSize} slotCount={config.slotCount}"
    ).err

  result = okVoid()

# ==============================================================================
# Construction / teardown
# ==============================================================================

proc openThreadtoolsVStreamRunner*(
  d: Detector;
  config: ThreadtoolsVStreamRunnerConfig
): HE[ThreadtoolsVStreamRunner] =
  ## Create a threadtools-based vstream runner from an already-opened Detector.
  ##
  ## submit() performs input write synchronously on the caller thread.  The
  ## output read is performed by an internal worker thread.  This keeps input
  ## buffers caller-owned and avoids copying large input frames into a shared
  ## slot buffer.
  if d.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "detector is nil").err

  if not d.isActivated():
    return makeError(HAILO_INVALID_OPERATION, "detector is not activated").err

  if d.inputVstream.isNil or d.inputVstream.raw.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "input vstream is nil").err

  if d.outputVstream.isNil or d.outputVstream.raw.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "output vstream is nil").err

  let configRes = validateConfig(config)
  if configRes.isErr:
    return configRes.error.err

  var readReqQRes = newThreadQueue[ReadRequest](config.inputQueueSize)
  if readReqQRes.isErr:
    return threadtoolsError(readReqQRes.error, "new read request queue").err

  var doneQRes = newThreadQueue[DoneResult](config.resultQueueSize)
  if doneQRes.isErr:
    return threadtoolsError(doneQRes.error, "new result queue").err

  var r = ThreadtoolsVStreamRunner()
  r.detector = d
  r.config = config
  r.state.outputRaw = d.outputVstream.raw
  r.state.outputSize = d.outputSize()
  r.state.slotCount = config.slotCount
  r.state.readReqQ = readReqQRes.get()
  r.state.doneQ = doneQRes.get()
  r.state.slots = cast[ptr UncheckedArray[OutputSlot]](
    allocShared0(sizeof(OutputSlot) * config.slotCount)
  )

  if r.state.slots.isNil:
    r.state.closeQueues()
    return makeError(HAILO_OUT_OF_HOST_MEMORY, "failed to allocate output slots").err

  for i in 0 ..< config.slotCount:
    r.state.slots[i].output = allocShared0(r.state.outputSize)

    if r.state.slots[i].output.isNil:
      r.state.closeQueues()
      r.state.freeOutputSlots()
      return makeError(HAILO_OUT_OF_HOST_MEMORY, "failed to allocate output buffer").err

    r.freeSlots.add(i)

  createThread(r.readThread, readMain, addr r.state)
  r.running = true

  result = r.ok

proc openThreadtoolsVStreamRunner*(d: Detector): HE[ThreadtoolsVStreamRunner] =
  result = d.openThreadtoolsVStreamRunner(defaultThreadtoolsVStreamRunnerConfig())

proc close*(r: ThreadtoolsVStreamRunner): HE[void] =
  if r.isNil:
    return okVoid()

  if r.running:
    var stopReq = ReadRequest(slotIndex: -1, writeUs: 0)
    let sendRes = r.state.readReqQ.sendMove(stopReq)
    if sendRes.isErr:
      r.state.closeQueues()
      return threadtoolsError(sendRes.error, "send stop request").err

    joinThread(r.readThread)
    r.running = false

  r.state.closeQueues()
  r.state.freeOutputSlots()
  r.freeSlots.setLen(0)
  r.detector = nil

  result = okVoid()

# ==============================================================================
# Introspection
# ==============================================================================

proc config*(r: ThreadtoolsVStreamRunner): ThreadtoolsVStreamRunnerConfig =
  if r.isNil:
    return defaultThreadtoolsVStreamRunnerConfig()

  result = r.config

proc slotCount*(r: ThreadtoolsVStreamRunner): int =
  if r.isNil:
    return 0

  result = r.state.slotCount

proc inputSize*(r: ThreadtoolsVStreamRunner): int =
  if r.isNil or r.detector.isNil:
    return 0

  result = r.detector.inputSize()

proc outputSize*(r: ThreadtoolsVStreamRunner): int =
  if r.isNil:
    return 0

  result = r.state.outputSize

proc outputPtr*(r: ThreadtoolsVStreamRunner; slotIndex: int): pointer =
  if r.isNil or slotIndex < 0 or slotIndex >= r.state.slotCount:
    return nil

  result = r.state.slots[slotIndex].output

proc availableSlots*(r: ThreadtoolsVStreamRunner): int =
  if r.isNil:
    return 0

  result = r.freeSlots.len

proc isRunning*(r: ThreadtoolsVStreamRunner): bool =
  if r.isNil:
    return false

  result = r.running

# ==============================================================================
# Submit / receive / release
# ==============================================================================

proc submit*(
  r: ThreadtoolsVStreamRunner;
  input: openArray[byte]
): HE[int] =
  ## Write one input frame and request the read worker to read the output.
  ##
  ## Returns the output slot index reserved for this submission.
  ##
  ## The input buffer is not copied. inputVstream.write() is called
  ## synchronously, and after it returns the caller may reuse input.
  if r.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "threadtools vstream runner is nil").err

  if not r.running:
    return makeError(HAILO_INVALID_OPERATION, "threadtools vstream runner is not running").err

  if r.detector.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "detector is nil").err

  if input.len != r.detector.inputSize():
    return makeError(
      HAILO_INVALID_ARGUMENT,
      &"input size mismatch: expected={r.detector.inputSize()} actual={input.len}"
    ).err

  if r.freeSlots.len == 0:
    return makeError(HAILO_QUEUE_IS_FULL, "no free output slot").err

  let slotIndex = r.freeSlots.pop()
  let started = getMonoTime()
  let writeRes = r.detector.inputVstream.write(input)
  let writeUs = elapsedUs(started)

  if writeRes.isErr:
    r.freeSlots.add(slotIndex)
    return writeRes.error.err

  var req = ReadRequest(slotIndex: slotIndex, writeUs: writeUs)
  let sendRes = r.state.readReqQ.sendMove(req)

  if sendRes.isErr:
    r.freeSlots.add(slotIndex)
    return threadtoolsError(sendRes.error, "send read request").err

  result = slotIndex.ok

proc waitResult*(r: ThreadtoolsVStreamRunner): HE[ThreadtoolsVStreamResult] =
  ## Wait for one completed output read.
  ##
  ## The returned slot must be released with releaseResult() after the caller has
  ## consumed outputPtr.
  if r.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "threadtools vstream runner is nil").err

  if not r.running:
    return makeError(HAILO_INVALID_OPERATION, "threadtools vstream runner is not running").err

  var doneRes = r.state.doneQ.receiveResult()
  if doneRes.isErr:
    return threadtoolsError(doneRes.error, "receive result").err

  var done = doneRes.take()

  let statusRes = statusResult(done.status, "threadtools vstream result")
  if statusRes.isErr:
    if done.slotIndex >= 0 and done.slotIndex < r.state.slotCount:
      r.freeSlots.add(done.slotIndex)
    return statusRes.error.err

  if done.slotIndex < 0 or done.slotIndex >= r.state.slotCount:
    return makeError(HAILO_INVALID_ARGUMENT, "slot index out of range").err

  result = ThreadtoolsVStreamResult(
    slotIndex: done.slotIndex,
    outputPtr: r.state.slots[done.slotIndex].output,
    outputSize: r.state.outputSize,
    writeUs: done.writeUs,
    readUs: done.readUs
  ).ok

proc tryWaitResult*(
  r: ThreadtoolsVStreamRunner;
  outResult: var ThreadtoolsVStreamResult
): HE[bool] =
  ## Non-blocking receive for one completed output read.
  ##
  ## Returns ok(false) when no completed result is available.
  if r.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "threadtools vstream runner is nil").err

  if not r.running:
    return makeError(HAILO_INVALID_OPERATION, "threadtools vstream runner is not running").err

  var done: DoneResult
  let recvRes = r.state.doneQ.tryReceive(done)
  if recvRes.isErr:
    return threadtoolsError(recvRes.error, "try receive result").err

  if not recvRes.get():
    return false.ok

  let statusRes = statusResult(done.status, "threadtools vstream result")
  if statusRes.isErr:
    if done.slotIndex >= 0 and done.slotIndex < r.state.slotCount:
      r.freeSlots.add(done.slotIndex)
    return statusRes.error.err

  if done.slotIndex < 0 or done.slotIndex >= r.state.slotCount:
    return makeError(HAILO_INVALID_ARGUMENT, "slot index out of range").err

  outResult = ThreadtoolsVStreamResult(
    slotIndex: done.slotIndex,
    outputPtr: r.state.slots[done.slotIndex].output,
    outputSize: r.state.outputSize,
    writeUs: done.writeUs,
    readUs: done.readUs
  )

  result = true.ok

proc releaseResult*(r: ThreadtoolsVStreamRunner; res: ThreadtoolsVStreamResult): HE[void] =
  ## Release an output slot returned by waitResult() / tryWaitResult().
  if r.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "threadtools vstream runner is nil").err

  if res.slotIndex < 0 or res.slotIndex >= r.state.slotCount:
    return makeError(HAILO_INVALID_ARGUMENT, "slot index out of range").err

  r.freeSlots.add(res.slotIndex)
  result = okVoid()
