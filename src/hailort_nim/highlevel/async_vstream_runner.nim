import std/[monotimes, strformat, times]

import ./detector
import ../lowlevel
import ../bindings/[c_api, types]
import ../internal/[error, helper]

type
  AsyncVStreamResult* = object
    ## Completed output slot.
    ##
    ## The output buffer remains owned by AsyncVStreamRunner.  The caller may read
    ## outputPtr until releaseResult() is called for this slot.
    slotIndex*: int
    outputPtr*: pointer
    outputSize*: int
    writeUs*: int64
    readUs*: int64

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

  AsyncVStreamState = object
    outputRaw: hailo_output_vstream
    outputSize: int
    slots: ptr UncheckedArray[OutputSlot]
    slotCount: int
    readReqCh: Channel[ReadRequest]
    doneCh: Channel[DoneResult]

  AsyncVStreamRunner* = ref object
    ## Generic vstream runner with a dedicated output read thread.
    ##
    ## This is model-output agnostic. It only handles:
    ##
    ##   main thread: input vstream write
    ##   read thread: output vstream read
    ##
    ## Higher-level code is responsible for parsing output bytes.
    ##
    ## The source Detector must stay alive and activated until close() returns.
    detector: Detector
    state: AsyncVStreamState
    readThread: Thread[ptr AsyncVStreamState]
    freeSlots: seq[int]
    running: bool

# ------------------------------------------------------------------------------
#
# elapsedUs:
#
# ------------------------------------------------------------------------------

proc elapsedUs(started: MonoTime): int64 {.inline.} =
  result = inMicroseconds(getMonoTime() - started)

# ------------------------------------------------------------------------------
#
# statusResult:
#
# ------------------------------------------------------------------------------

proc statusResult(status: hailo_status; where: string): HE[void] =
  if status != HAILO_SUCCESS:
    return makeError(status, &"{where}: {status}").err

  result = okVoid()

# ------------------------------------------------------------------------------
#
# freeOutputSlots:
#
# ------------------------------------------------------------------------------

proc freeOutputSlots(state: var AsyncVStreamState) =
  if state.slots.isNil:
    return

  for i in 0 ..< state.slotCount:
    if not state.slots[i].output.isNil:
      deallocShared(state.slots[i].output)
      state.slots[i].output = nil

  deallocShared(state.slots)
  state.slots = nil
  state.slotCount = 0

# ------------------------------------------------------------------------------
#
# readMain:
#
# ------------------------------------------------------------------------------

proc readMain(state: ptr AsyncVStreamState) {.thread.} =
  while true:
    let req = state.readReqCh.recv()

    if req.slotIndex < 0:
      break

    if req.slotIndex >= state.slotCount:
      state.doneCh.send(DoneResult(
        slotIndex: req.slotIndex,
        status: HAILO_INVALID_ARGUMENT,
        writeUs: req.writeUs,
        readUs: 0
      ))
      continue

    let slot = state.slots[req.slotIndex]
    let started = getMonoTime()
    let status = hailo_vstream_read_raw_buffer(
      state.outputRaw,
      slot.output,
      csize_t(state.outputSize)
    )
    let readUs = elapsedUs(started)

    state.doneCh.send(DoneResult(
      slotIndex: req.slotIndex,
      status: status,
      writeUs: req.writeUs,
      readUs: readUs
    ))

# ------------------------------------------------------------------------------
#
# openAsyncVStreamRunner:
#
# ------------------------------------------------------------------------------

proc openAsyncVStreamRunner*(
  d: Detector;
  slotCount = 2
): HE[AsyncVStreamRunner] =
  ## Create an async-style vstream runner from an already-opened Detector.
  ##
  ## submit() performs input write synchronously on the caller thread.
  ## The output read is performed by an internal read thread.
  ##
  ## This keeps input buffers caller-owned and avoids copying 640x640 RGB input
  ## into a shared slot buffer.
  if d.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "detector is nil").err

  if not d.isActivated():
    return makeError(HAILO_INVALID_OPERATION, "detector is not activated").err

  if d.inputVstream.isNil or d.inputVstream.raw.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "input vstream is nil").err

  if d.outputVstream.isNil or d.outputVstream.raw.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "output vstream is nil").err

  if slotCount <= 0:
    return makeError(HAILO_INVALID_ARGUMENT, "slotCount must be positive").err

  var r = AsyncVStreamRunner()
  r.detector = d
  r.state.outputRaw = d.outputVstream.raw
  r.state.outputSize = d.outputSize()
  r.state.slotCount = slotCount
  r.state.slots = cast[ptr UncheckedArray[OutputSlot]](
    allocShared0(sizeof(OutputSlot) * slotCount)
  )

  if r.state.slots.isNil:
    return makeError(HAILO_OUT_OF_HOST_MEMORY, "failed to allocate output slots").err

  for i in 0 ..< slotCount:
    r.state.slots[i].output = allocShared0(r.state.outputSize)

    if r.state.slots[i].output.isNil:
      r.state.freeOutputSlots()
      return makeError(HAILO_OUT_OF_HOST_MEMORY, "failed to allocate output buffer").err

    r.freeSlots.add(i)

  r.state.readReqCh.open()
  r.state.doneCh.open()

  createThread(r.readThread, readMain, addr r.state)
  r.running = true

  result = r.ok

# ------------------------------------------------------------------------------
#
# close:
#
# ------------------------------------------------------------------------------

proc close*(r: AsyncVStreamRunner): HE[void] =
  if r.isNil:
    return okVoid()

  if r.running:
    r.state.readReqCh.send(ReadRequest(slotIndex: -1, writeUs: 0))
    joinThread(r.readThread)
    r.running = false

  r.state.readReqCh.close()
  r.state.doneCh.close()
  r.state.freeOutputSlots()
  r.freeSlots.setLen(0)
  r.detector = nil

  result = okVoid()

# ------------------------------------------------------------------------------
#
# slotCount:
#
# ------------------------------------------------------------------------------

proc slotCount*(r: AsyncVStreamRunner): int =
  if r.isNil:
    return 0

  result = r.state.slotCount

# ------------------------------------------------------------------------------
#
# inputSize:
#
# ------------------------------------------------------------------------------

proc inputSize*(r: AsyncVStreamRunner): int =
  if r.isNil or r.detector.isNil:
    return 0

  result = r.detector.inputSize()

# ------------------------------------------------------------------------------
#
# outputSize:
#
# ------------------------------------------------------------------------------

proc outputSize*(r: AsyncVStreamRunner): int =
  if r.isNil:
    return 0

  result = r.state.outputSize

# ------------------------------------------------------------------------------
#
# outputPtr:
#
# ------------------------------------------------------------------------------

proc outputPtr*(r: AsyncVStreamRunner; slotIndex: int): pointer =
  if r.isNil or slotIndex < 0 or slotIndex >= r.state.slotCount:
    return nil

  result = r.state.slots[slotIndex].output

# ------------------------------------------------------------------------------
#
# availableSlots:
#
# ------------------------------------------------------------------------------

proc availableSlots*(r: AsyncVStreamRunner): int =
  if r.isNil:
    return 0

  result = r.freeSlots.len

# ------------------------------------------------------------------------------
#
# submit:
#
# ------------------------------------------------------------------------------

proc submit*(
  r: AsyncVStreamRunner;
  input: openArray[byte]
): HE[int] =
  ## Write one input frame and request the read thread to read the output.
  ##
  ## Returns the output slot index reserved for this submission.
  ##
  ## The input buffer is not copied. inputVstream.write() is called
  ## synchronously, and after it returns the caller may reuse input.
  if r.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "async vstream runner is nil").err

  if not r.running:
    return makeError(HAILO_INVALID_OPERATION, "async vstream runner is not running").err

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

  r.state.readReqCh.send(ReadRequest(
    slotIndex: slotIndex,
    writeUs: writeUs
  ))

  result = slotIndex.ok

# ------------------------------------------------------------------------------
#
# waitResult:
#
# ------------------------------------------------------------------------------

proc waitResult*(r: AsyncVStreamRunner): HE[AsyncVStreamResult] =
  ## Wait for one completed output read.
  ##
  ## The returned slot must be released with releaseResult() after the caller has
  ## consumed outputPtr.
  if r.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "async vstream runner is nil").err

  if not r.running:
    return makeError(HAILO_INVALID_OPERATION, "async vstream runner is not running").err

  let done = r.state.doneCh.recv()
  let statusRes = statusResult(done.status, "async vstream result")

  if statusRes.isErr:
    r.freeSlots.add(done.slotIndex)
    return statusRes.error.err

  result = AsyncVStreamResult(
    slotIndex: done.slotIndex,
    outputPtr: r.state.slots[done.slotIndex].output,
    outputSize: r.state.outputSize,
    writeUs: done.writeUs,
    readUs: done.readUs
  ).ok

# ------------------------------------------------------------------------------
#
# releaseResult:
#
# ------------------------------------------------------------------------------

proc releaseResult*(r: AsyncVStreamRunner; res: AsyncVStreamResult): HE[void] =
  ## Release an output slot returned by waitResult().
  if r.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "async vstream runner is nil").err

  if res.slotIndex < 0 or res.slotIndex >= r.state.slotCount:
    return makeError(HAILO_INVALID_ARGUMENT, "slot index out of range").err

  r.freeSlots.add(res.slotIndex)
  result = okVoid()
