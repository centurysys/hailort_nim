when not compileOption("threads"):
  {.error: "threadtools_inference_worker requires --threads:on".}

import std/[monotimes, strformat, times]

import threadtools/thread_queue
import threadtools/pooled
import threadtools/pool_item
import threadtools/lib/errcode

import ./detector
import ./inference_parser
import ./inference_result
import ./threadtools_vstream_runner
import ../lowlevel
import ../bindings/c_api
import ../internal/error

# ==============================================================================
# Public types
# ==============================================================================

type
  ThreadtoolsInferenceWorkerConfig* = object
    ## Queue and parser configuration for a generic HAILO inference worker.
    ##
    ## The worker owns a ThreadtoolsVStreamRunner and executes input submit,
    ## output wait, and parser dispatch on its worker thread.  Result payloads are
    ## moved back through a ThreadQueue and should be received with
    ## waitReply(reply: var ThreadtoolsInferenceWorkerReply) to avoid Result.get()
    ## copies on large RawTensorResult values.
    requestQueueSize*: int
    replyQueueSize*: int
    parserConfig*: HailoOutputParserConfig

  ThreadtoolsInferenceWorkerRequestKind* = enum
    ## Request payload kind for ThreadtoolsInferenceWorker.
    tiwrkReqStop
    tiwrkReqSeq
    tiwrkReqPooledSeq

  ThreadtoolsInferenceWorkerRequest* = object
    ## One inference request for ThreadtoolsInferenceWorker.
    ##
    ## The worker accepts either an owned seq[byte] or a threadtools
    ## Pooled[seq[byte]] / PoolItem[seq[byte]] token.  requestId and userData are
    ## opaque caller-supplied correlation fields copied to replies and parsed
    ## HailoInferenceResult values.
    kind*: ThreadtoolsInferenceWorkerRequestKind
    requestId*: uint64
    userData*: uint64
    input*: seq[byte]
    pooledInput*: Pooled[seq[byte]]

  ThreadtoolsInferenceWorkerResult* = object
    ## Successful inference result returned by ThreadtoolsInferenceWorker.
    requestId*: uint64
    userData*: uint64
    inference*: HailoInferenceResult

  ThreadtoolsInferenceWorkerError* = object
    ## Job-level error payload that is safe to move across ThreadQueue.
    ##
    ## HailoError itself is a ref object, so worker replies carry only copyable /
    ## movable status+message data.  Convert it back with toHailoError() if a
    ## normal HE-style error is needed.
    status*: hailo_status
    msg*: string

  ThreadtoolsInferenceWorkerReplyKind* = enum
    tiwrkResult
    tiwrkError

  ThreadtoolsInferenceWorkerReply* = object
    ## Reply moved from the inference worker to the caller/control thread.
    ##
    ## Job-level HAILO errors are reported as tiwrkError replies so the caller can
    ## keep requestId/userData association.  Queue/worker state errors are returned
    ## from waitReply()/tryWaitReply() as HE errors.
    kind*: ThreadtoolsInferenceWorkerReplyKind
    requestId*: uint64
    userData*: uint64
    result*: ThreadtoolsInferenceWorkerResult
    error*: ThreadtoolsInferenceWorkerError

  ThreadtoolsInferenceWorkerState = object
    runner: ThreadtoolsVStreamRunner
    parserConfig: HailoOutputParserConfig
    outputMetadata: VStreamMetadata
    requestQ: ThreadQueue[ThreadtoolsInferenceWorkerRequest]
    replyQ: ThreadQueue[ThreadtoolsInferenceWorkerReply]

  ThreadtoolsInferenceWorker* = ref object
    ## Worker handle for queue-driven generic HAILO inference.
    ##
    ## This is intentionally separate from ThreadtoolsDetectorWorker.  Existing
    ## YOLO/NMS detector APIs remain compatible while this worker provides a
    ## parser-configurable path for raw tensor probing and future OCR/text models.
    runner: ThreadtoolsVStreamRunner
    requestQ: ThreadQueue[ThreadtoolsInferenceWorkerRequest]
    replyQ: ThreadQueue[ThreadtoolsInferenceWorkerReply]
    workerThread: Thread[ptr ThreadtoolsInferenceWorkerState]
    state: ThreadtoolsInferenceWorkerState
    config: ThreadtoolsInferenceWorkerConfig
    running: bool
    stopping: bool
    closed: bool

# ==============================================================================
# Lifetime hooks
# ==============================================================================

proc `=destroy`*(self: var ThreadtoolsInferenceWorkerRequest) {.raises: [].} =
  ## ThreadtoolsInferenceWorkerRequest can carry an active Pooled[seq[byte]].
  ##
  ## std/isolation checks the destructor effect of values passed through
  ## ThreadQueue.sendMove().  Even a tiwrkReqStop value has the pooledInput field
  ## at the type level, so relying on the compiler-generated object destructor can
  ## produce an Effect warning when PoolItem's auto-return path is involved.
  try:
    case self.kind
    of tiwrkReqSeq:
      `=destroy`(self.input)
    of tiwrkReqPooledSeq:
      `=destroy`(self.pooledInput)
    of tiwrkReqStop:
      `=destroy`(self.input)
  except Exception:
    discard

proc clear*(self: var ThreadtoolsInferenceWorkerResult) {.raises: [].} =
  ## Explicitly release result payloads before reusing or dropping a reply.
  try:
    self.inference.clear()
    self.requestId = 0'u64
    self.userData = 0'u64
  except Exception:
    discard

proc clear*(self: var ThreadtoolsInferenceWorkerError) {.raises: [].} =
  try:
    self.status = HAILO_SUCCESS
    self.msg.setLen(0)
  except Exception:
    discard

proc clear*(self: var ThreadtoolsInferenceWorkerReply) {.raises: [].} =
  ## Explicit reply cleanup for out-var style receive loops.
  ##
  ## This is useful for large RawTensorResult replies: callers can release the
  ## previous raw buffer at a predictable point instead of waiting for scope-exit
  ## destruction.
  try:
    case self.kind
    of tiwrkResult:
      self.result.clear()
    of tiwrkError:
      self.error.clear()
    self.requestId = 0'u64
    self.userData = 0'u64
  except Exception:
    discard

proc `=destroy`*(self: var ThreadtoolsInferenceWorkerResult) {.raises: [].} =
  self.clear()

proc `=destroy`*(self: var ThreadtoolsInferenceWorkerError) {.raises: [].} =
  self.clear()

proc `=destroy`*(self: var ThreadtoolsInferenceWorkerReply) {.raises: [].} =
  self.clear()

# ==============================================================================
# Small helpers
# ==============================================================================

proc elapsedUs(started: MonoTime): int64 {.inline.} =
  result = inMicroseconds(getMonoTime() - started)

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

proc toWorkerError(error: HailoError): ThreadtoolsInferenceWorkerError =
  if error.isNil:
    result.status = HAILO_INVALID_OPERATION
    result.msg = "unknown HAILO error"
  else:
    result.status = error.status
    result.msg = error.msg

proc toHailoError*(error: ThreadtoolsInferenceWorkerError): HailoError =
  result = makeError(error.status, error.msg)

proc makeErrorReply(
  requestId: uint64;
  userData: uint64;
  error: HailoError
): ThreadtoolsInferenceWorkerReply =
  result.kind = tiwrkError
  result.requestId = requestId
  result.userData = userData
  result.error = toWorkerError(error)

proc makeResultReply(
  requestId: uint64;
  userData: uint64;
  inference: sink HailoInferenceResult
): ThreadtoolsInferenceWorkerReply =
  result.kind = tiwrkResult
  result.requestId = requestId
  result.userData = userData
  result.result = ThreadtoolsInferenceWorkerResult(
    requestId: requestId,
    userData: userData,
    inference: move inference
  )

# ==============================================================================
# Worker main
# ==============================================================================

type
  PendingRequest = object
    requestId: uint64
    userData: uint64

proc inputLen(req: var ThreadtoolsInferenceWorkerRequest): int {.inline.} =
  case req.kind
  of tiwrkReqStop:
    result = 0
  of tiwrkReqSeq:
    result = req.input.len
  of tiwrkReqPooledSeq:
    if req.pooledInput.isActive:
      result = req.pooledInput.value.len
    else:
      result = 0

proc submitInput(
  runner: ThreadtoolsVStreamRunner;
  req: var ThreadtoolsInferenceWorkerRequest
): HE[int] =
  case req.kind
  of tiwrkReqStop:
    result = makeError(HAILO_INVALID_OPERATION, "stop request has no input").err
  of tiwrkReqSeq:
    result = runner.submit(req.input)
  of tiwrkReqPooledSeq:
    result = runner.submit(req.pooledInput.value)

proc sendWorkerReply(
  state: ptr ThreadtoolsInferenceWorkerState;
  reply: sink ThreadtoolsInferenceWorkerReply
) =
  var owned = move reply
  discard state.replyQ.sendMove(owned)

proc handleSubmitRequest(
  state: ptr ThreadtoolsInferenceWorkerState;
  req: sink ThreadtoolsInferenceWorkerRequest;
  pending: var seq[PendingRequest]
): bool =
  ## Returns false when the worker should stop accepting new requests.
  ##
  ## Pooled input items are intentionally scoped to this procedure.  The HAILO
  ## input vstream write is synchronous, so after submitInput() returns the
  ## source buffer may be returned to its pool immediately while the output read
  ## continues on the vstream runner's read worker.
  var ownedReq = move req

  if ownedReq.kind == tiwrkReqStop:
    return false

  if ownedReq.inputLen() == 0:
    var reply = makeErrorReply(
      ownedReq.requestId,
      ownedReq.userData,
      makeError(HAILO_INVALID_ARGUMENT, "inference worker request input is empty")
    )
    state.sendWorkerReply(move reply)
    return true

  let submitRes = state.runner.submitInput(ownedReq)
  if submitRes.isErr:
    var reply = makeErrorReply(ownedReq.requestId, ownedReq.userData, submitRes.error)
    state.sendWorkerReply(move reply)
    return true

  pending.add PendingRequest(
    requestId: ownedReq.requestId,
    userData: ownedReq.userData
  )
  result = true

proc receiveBlockingRequest(
  state: ptr ThreadtoolsInferenceWorkerState;
  pending: var seq[PendingRequest]
): bool =
  ## Blocks until one request is available.  Returns false on stop/queue error.
  var reqRes = state.requestQ.receiveResult()
  if reqRes.isErr:
    return false

  var req = reqRes.take()
  result = state.handleSubmitRequest(move req, pending)

proc tryReceiveRequest(
  state: ptr ThreadtoolsInferenceWorkerState;
  pending: var seq[PendingRequest]
): bool =
  ## Attempts to receive one request without blocking.
  var req: ThreadtoolsInferenceWorkerRequest
  let recvRes = state.requestQ.tryReceive(req)
  if recvRes.isErr:
    return false

  if not recvRes.get():
    return false

  result = state.handleSubmitRequest(move req, pending)

proc releaseVStreamResult(
  state: ptr ThreadtoolsInferenceWorkerState;
  vres: ThreadtoolsVStreamResult
): HE[void] =
  result = state.runner.releaseResult(vres)

proc parseVStreamResult(
  state: ptr ThreadtoolsInferenceWorkerState;
  pendingReq: PendingRequest;
  vres: ThreadtoolsVStreamResult;
  totalUs: int64;
  inference: var HailoInferenceResult
): HE[void] =
  var timing = HailoInferenceTiming(
    slotIndex: vres.slotIndex,
    writeUs: vres.writeUs,
    readUs: vres.readUs,
    parseUs: 0,
    sortUs: 0,
    totalUs: totalUs
  )

  result = state.parserConfig.parseOutputInto(
    vres.outputPtr,
    vres.outputSize,
    state.outputMetadata,
    inference,
    requestId = pendingReq.requestId,
    userData = pendingReq.userData,
    timing = timing,
    includeMetadataStrings = false
  )

proc inferenceWorkerMain(state: ptr ThreadtoolsInferenceWorkerState) {.thread.} =
  ## Pipelined generic inference worker.
  ##
  ## This mirrors ThreadtoolsDetectorWorker's queue-driven shape but delegates
  ## output conversion to HailoOutputParserConfig.  Stop requests stop accepting
  ## new input, but already-submitted requests are drained before thread exit.
  var pending: seq[PendingRequest] = @[]
  var accepting = true

  while true:
    while accepting and pending.len < state.runner.slotCount():
      if pending.len == 0:
        accepting = state.receiveBlockingRequest(pending)
      else:
        let acceptedOne = state.tryReceiveRequest(pending)
        if not acceptedOne:
          break

    if pending.len == 0:
      if not accepting:
        break
      continue

    let pendingReq = pending[0]
    let started = getMonoTime()
    let waitRes = state.runner.waitResult()
    let totalUs = elapsedUs(started)
    pending.delete(0)

    if waitRes.isErr:
      var reply = makeErrorReply(pendingReq.requestId, pendingReq.userData, waitRes.error)
      state.sendWorkerReply(move reply)
      continue

    let vres = waitRes.get()
    var inference: HailoInferenceResult
    let parseRes = state.parseVStreamResult(pendingReq, vres, totalUs, inference)
    let releaseRes = state.releaseVStreamResult(vres)

    if parseRes.isErr:
      var reply = makeErrorReply(pendingReq.requestId, pendingReq.userData, parseRes.error)
      state.sendWorkerReply(move reply)
      continue

    if releaseRes.isErr:
      var reply = makeErrorReply(pendingReq.requestId, pendingReq.userData, releaseRes.error)
      state.sendWorkerReply(move reply)
      continue

    var reply = makeResultReply(
      pendingReq.requestId,
      pendingReq.userData,
      move inference
    )
    state.sendWorkerReply(move reply)

# ==============================================================================
# Configuration
# ==============================================================================

proc recommendedThreadtoolsInferenceWorkerRequestQueueSize*(slotCount: int): int =
  ## Recommended request queue depth for benchmark-style single-threaded
  ## submit/recv loops.
  if slotCount <= 0:
    return 2

  result = max(2, slotCount * 2)

proc initThreadtoolsInferenceWorkerConfig*(
  slotCount: int;
  parserConfig: HailoOutputParserConfig
): ThreadtoolsInferenceWorkerConfig =
  let requestQueueSize = recommendedThreadtoolsInferenceWorkerRequestQueueSize(slotCount)
  result = ThreadtoolsInferenceWorkerConfig(
    requestQueueSize: requestQueueSize,
    replyQueueSize: requestQueueSize + 1,
    parserConfig: parserConfig
  )

proc defaultThreadtoolsInferenceWorkerConfig*(slotCount = 2): ThreadtoolsInferenceWorkerConfig =
  result = initThreadtoolsInferenceWorkerConfig(
    slotCount,
    defaultRawTensorParserConfig()
  )

proc validateConfig(config: ThreadtoolsInferenceWorkerConfig): HE[void] =
  if config.requestQueueSize <= 0:
    return makeError(HAILO_INVALID_ARGUMENT, "requestQueueSize must be positive").err

  if config.replyQueueSize <= 0:
    return makeError(HAILO_INVALID_ARGUMENT, "replyQueueSize must be positive").err

  if config.replyQueueSize < config.requestQueueSize + 1:
    return makeError(
      HAILO_INVALID_ARGUMENT,
      &"replyQueueSize must be >= requestQueueSize + 1: replyQueueSize={config.replyQueueSize} requestQueueSize={config.requestQueueSize}"
    ).err

  let parserRes = config.parserConfig.validateParserConfig()
  if parserRes.isErr:
    return parserRes.error.err

  result = okVoid()

# ==============================================================================
# Construction / teardown
# ==============================================================================

proc startThreadtoolsInferenceWorker*(
  runner: ThreadtoolsVStreamRunner;
  config: ThreadtoolsInferenceWorkerConfig
): HE[ThreadtoolsInferenceWorker] =
  ## Start a queue-driven generic inference worker.
  ##
  ## Ownership note: after this succeeds, the worker owns runner.  Do not call
  ## runner directly or close it separately.  close(worker) sends the stop
  ## request, joins the worker thread, and then closes runner on the owner thread.
  if runner.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "threadtools vstream runner is nil").err

  if not runner.isRunning():
    return makeError(HAILO_INVALID_OPERATION, "threadtools vstream runner is not running").err

  let configRes = validateConfig(config)
  if configRes.isErr:
    return configRes.error.err

  let outputMetadataRes = runner.outputMetadata()
  if outputMetadataRes.isErr:
    return outputMetadataRes.error.err

  var requestQRes = newThreadQueue[ThreadtoolsInferenceWorkerRequest](
    config.requestQueueSize
  )
  if requestQRes.isErr:
    return threadtoolsError(requestQRes.error, "new inference worker request queue").err

  var replyQRes = newThreadQueue[ThreadtoolsInferenceWorkerReply](
    config.replyQueueSize
  )
  if replyQRes.isErr:
    return threadtoolsError(replyQRes.error, "new inference worker reply queue").err

  var w = ThreadtoolsInferenceWorker()
  w.runner = runner
  w.requestQ = requestQRes.get()
  w.replyQ = replyQRes.get()
  w.config = config
  w.state.runner = runner
  w.state.parserConfig = config.parserConfig
  w.state.outputMetadata = outputMetadataRes.get()
  w.state.requestQ = w.requestQ
  w.state.replyQ = w.replyQ

  createThread(w.workerThread, inferenceWorkerMain, addr w.state)
  w.running = true

  result = w.ok

proc startThreadtoolsInferenceWorker*(
  runner: ThreadtoolsVStreamRunner;
  parserConfig: HailoOutputParserConfig
): HE[ThreadtoolsInferenceWorker] =
  let slotCount = runner.slotCount()
  result = runner.startThreadtoolsInferenceWorker(
    initThreadtoolsInferenceWorkerConfig(slotCount, parserConfig)
  )

proc startThreadtoolsInferenceWorker*(
  runner: ThreadtoolsVStreamRunner
): HE[ThreadtoolsInferenceWorker] =
  result = runner.startThreadtoolsInferenceWorker(
    defaultThreadtoolsInferenceWorkerConfig(runner.slotCount())
  )

proc startThreadtoolsInferenceWorker*(
  d: Detector;
  runnerConfig: ThreadtoolsVStreamRunnerConfig;
  workerConfig: ThreadtoolsInferenceWorkerConfig
): HE[ThreadtoolsInferenceWorker] =
  ## Build a ThreadtoolsVStreamRunner from an activated Detector and start a
  ## generic inference worker.
  let runnerRes = d.openThreadtoolsVStreamRunner(runnerConfig)
  if runnerRes.isErr:
    return runnerRes.error.err

  let runner = runnerRes.get()
  let workerRes = runner.startThreadtoolsInferenceWorker(workerConfig)
  if workerRes.isErr:
    discard runner.close()
    return workerRes.error.err

  result = workerRes

proc startThreadtoolsInferenceWorker*(
  d: Detector;
  parserConfig: HailoOutputParserConfig;
  slotCount = 2;
  requestQueueSize = 0
): HE[ThreadtoolsInferenceWorker] =
  var runnerConfig = defaultThreadtoolsVStreamRunnerConfig()
  runnerConfig.slotCount = slotCount
  runnerConfig.inputQueueSize = slotCount
  runnerConfig.resultQueueSize = slotCount

  let effectiveRequestQueueSize =
    if requestQueueSize > 0:
      requestQueueSize
    else:
      recommendedThreadtoolsInferenceWorkerRequestQueueSize(slotCount)

  var workerConfig = initThreadtoolsInferenceWorkerConfig(slotCount, parserConfig)
  workerConfig.requestQueueSize = effectiveRequestQueueSize
  workerConfig.replyQueueSize = effectiveRequestQueueSize + 1

  result = d.startThreadtoolsInferenceWorker(runnerConfig, workerConfig)

proc startThreadtoolsInferenceWorker*(
  d: Detector;
  slotCount = 2;
  requestQueueSize = 0
): HE[ThreadtoolsInferenceWorker] =
  result = d.startThreadtoolsInferenceWorker(
    defaultRawTensorParserConfig(),
    slotCount,
    requestQueueSize
  )

proc stop*(w: ThreadtoolsInferenceWorker): HE[void] =
  ## Request a graceful worker stop.
  ##
  ## stop() is idempotent.  It tells the worker to stop accepting new requests.
  ## Requests already submitted to HAILO are drained before the worker thread exits.
  if w.isNil:
    return okVoid()

  if w.closed or not w.running or w.stopping:
    return okVoid()

  if w.requestQ.isNil:
    return makeError(HAILO_INVALID_OPERATION, "inference worker request queue is nil").err

  var stopReq = ThreadtoolsInferenceWorkerRequest(
    kind: tiwrkReqStop,
    requestId: 0'u64,
    userData: 0'u64,
    input: @[]
  )
  let sendRes = w.requestQ.sendMove(stopReq)
  if sendRes.isErr:
    return threadtoolsError(sendRes.error, "send inference worker stop request").err

  w.stopping = true
  result = okVoid()

proc join*(w: ThreadtoolsInferenceWorker): HE[void] =
  ## Wait for the inference worker to exit and release its owned resources.
  if w.isNil:
    return okVoid()

  if w.closed:
    return okVoid()

  if w.running:
    if not w.stopping:
      let stopRes = w.stop()
      if stopRes.isErr:
        return stopRes.error.err

    joinThread(w.workerThread)
    w.running = false
    w.stopping = false

  if not w.runner.isNil:
    let closeRes = w.runner.close()
    if closeRes.isErr:
      return closeRes.error.err

  if not w.requestQ.isNil:
    w.requestQ.close()
  if not w.replyQ.isNil:
    w.replyQ.close()

  w.runner = nil
  w.state.runner = nil
  w.requestQ = nil
  w.replyQ = nil
  w.state.requestQ = nil
  w.state.replyQ = nil
  w.closed = true

  result = okVoid()

proc close*(w: ThreadtoolsInferenceWorker): HE[void] =
  ## Stop and join the inference worker.
  result = w.join()

# ==============================================================================
# Introspection
# ==============================================================================

proc config*(w: ThreadtoolsInferenceWorker): ThreadtoolsInferenceWorkerConfig =
  if w.isNil:
    return defaultThreadtoolsInferenceWorkerConfig()

  result = w.config

proc isRunning*(w: ThreadtoolsInferenceWorker): bool =
  if w.isNil:
    return false

  result = w.running

proc isStopping*(w: ThreadtoolsInferenceWorker): bool =
  if w.isNil:
    return false

  result = w.stopping

proc isClosed*(w: ThreadtoolsInferenceWorker): bool =
  if w.isNil:
    return true

  result = w.closed

proc inputSize*(w: ThreadtoolsInferenceWorker): int =
  if w.isNil or w.runner.isNil:
    return 0

  result = w.runner.inputSize()

proc outputSize*(w: ThreadtoolsInferenceWorker): int =
  if w.isNil or w.runner.isNil:
    return 0

  result = w.runner.outputSize()

proc outputMetadata*(w: ThreadtoolsInferenceWorker): VStreamMetadata =
  if w.isNil:
    return VStreamMetadata()

  result = w.state.outputMetadata

# ==============================================================================
# Submit / receive
# ==============================================================================

proc submit*(
  w: ThreadtoolsInferenceWorker;
  input: sink seq[byte];
  requestId: uint64 = 0'u64;
  userData: uint64 = 0'u64
): HE[void] =
  ## Submit an owned seq[byte] input buffer to the inference worker.
  if w.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "inference worker is nil").err

  if w.closed:
    return makeError(HAILO_INVALID_OPERATION, "inference worker is closed").err

  if w.stopping:
    return makeError(HAILO_INVALID_OPERATION, "inference worker is stopping").err

  if not w.running:
    return makeError(HAILO_INVALID_OPERATION, "inference worker is not running").err

  if input.len == 0:
    return makeError(HAILO_INVALID_ARGUMENT, "input is empty").err

  if w.inputSize() > 0 and input.len != w.inputSize():
    return makeError(
      HAILO_INVALID_ARGUMENT,
      &"input size mismatch: expected={w.inputSize()} actual={input.len}"
    ).err

  var req = ThreadtoolsInferenceWorkerRequest(
    kind: tiwrkReqSeq,
    requestId: requestId,
    userData: userData,
    input: move input
  )
  let sendRes = w.requestQ.sendMove(req)
  if sendRes.isErr:
    return threadtoolsError(sendRes.error, "send inference worker request").err

  result = okVoid()

proc submitPooled*(
  w: ThreadtoolsInferenceWorker;
  input: sink Pooled[seq[byte]];
  requestId: uint64 = 0'u64;
  userData: uint64 = 0'u64
): HE[void] =
  ## Submit a pooled input buffer to the inference worker.
  if w.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "inference worker is nil").err

  if w.closed:
    return makeError(HAILO_INVALID_OPERATION, "inference worker is closed").err

  if w.stopping:
    return makeError(HAILO_INVALID_OPERATION, "inference worker is stopping").err

  if not w.running:
    return makeError(HAILO_INVALID_OPERATION, "inference worker is not running").err

  var ownedInput = move input
  if not ownedInput.isActive:
    return makeError(HAILO_INVALID_ARGUMENT, "pooled input is not active").err

  if ownedInput.value.len == 0:
    return makeError(HAILO_INVALID_ARGUMENT, "input is empty").err

  if w.inputSize() > 0 and ownedInput.value.len != w.inputSize():
    return makeError(
      HAILO_INVALID_ARGUMENT,
      &"input size mismatch: expected={w.inputSize()} actual={ownedInput.value.len}"
    ).err

  var req = ThreadtoolsInferenceWorkerRequest(
    kind: tiwrkReqPooledSeq,
    requestId: requestId,
    userData: userData,
    pooledInput: move ownedInput
  )
  let sendRes = w.requestQ.sendMove(req)
  if sendRes.isErr:
    return threadtoolsError(sendRes.error, "send inference worker pooled request").err

  result = okVoid()

proc submitPoolItem*(
  w: ThreadtoolsInferenceWorker;
  input: sink Pooled[seq[byte]];
  requestId: uint64 = 0'u64;
  userData: uint64 = 0'u64
): HE[void] {.inline.} =
  ## Alias for submitPooled().
  result = w.submitPooled(move input, requestId, userData)

proc submitCopy*(
  w: ThreadtoolsInferenceWorker;
  input: openArray[byte];
  requestId: uint64 = 0'u64;
  userData: uint64 = 0'u64
): HE[void] =
  ## Submit a borrowed input buffer by copying it into an owned seq[byte].
  var owned = newSeq[byte](input.len)
  if input.len > 0:
    copyMem(addr owned[0], unsafeAddr input[0], input.len)

  result = w.submit(move owned, requestId, userData)

proc waitReply*(
  w: ThreadtoolsInferenceWorker;
  reply: var ThreadtoolsInferenceWorkerReply
): HE[void] =
  ## Blocking receive of one worker reply.
  ##
  ## The reply is moved into caller-provided storage to avoid wrapping a large
  ## HailoInferenceResult in Result[T, E] and extracting it with .get().
  if w.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "inference worker is nil").err

  if w.closed:
    return makeError(HAILO_INVALID_OPERATION, "inference worker is closed").err

  var recvRes = w.replyQ.receiveResult()
  if recvRes.isErr:
    return threadtoolsError(recvRes.error, "receive inference worker reply").err

  var tmp = recvRes.take()
  reply = move tmp
  result = okVoid()

proc recv*(
  w: ThreadtoolsInferenceWorker;
  reply: var ThreadtoolsInferenceWorkerReply
): HE[void] {.inline.} =
  result = w.waitReply(reply)

proc tryWaitReply*(
  w: ThreadtoolsInferenceWorker;
  reply: var ThreadtoolsInferenceWorkerReply
): HE[bool] =
  ## Non-blocking receive of one worker reply.
  if w.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "inference worker is nil").err

  if w.closed:
    return makeError(HAILO_INVALID_OPERATION, "inference worker is closed").err

  var tmp: ThreadtoolsInferenceWorkerReply
  let recvRes = w.replyQ.tryReceive(tmp)
  if recvRes.isErr:
    return threadtoolsError(recvRes.error, "try receive inference worker reply").err

  if not recvRes.get():
    return false.ok

  reply = move tmp
  result = true.ok

proc tryRecv*(
  w: ThreadtoolsInferenceWorker;
  reply: var ThreadtoolsInferenceWorkerReply
): HE[bool] {.inline.} =
  result = w.tryWaitReply(reply)
