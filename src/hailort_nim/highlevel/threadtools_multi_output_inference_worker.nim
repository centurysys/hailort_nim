when not compileOption("threads"):
  {.error: "threadtools_multi_output_inference_worker requires --threads:on".}

import std/[monotimes, strformat, times]

import threadtools/thread_queue
import threadtools/pooled
import threadtools/pool_item
import threadtools/lib/errcode

import ./inference_result
import ./multi_output_inference
import ./yolov8_pose_parser
import ../lowlevel
import ../bindings/c_api
import ../internal/error

# ==============================================================================
# Public types
# ==============================================================================

type
  ThreadtoolsMultiOutputParserKind* = enum
    ## Parser kind for ThreadtoolsMultiOutputInferenceWorker.
    ##
    ## Only YOLOv8 pose is implemented for now.  This enum is intentionally kept
    ## so future multi-output parsers can be added without changing the worker
    ## queue/reply API shape.
    tmopYolov8Pose

  ThreadtoolsMultiOutputInferenceWorkerConfig* = object
    ## Queue and parser configuration for a multi-output inference worker.
    requestQueueSize*: int
    replyQueueSize*: int
    parserKind*: ThreadtoolsMultiOutputParserKind
    yolov8Pose*: Yolov8PoseParserConfig

  ThreadtoolsMultiOutputInferenceWorkerRequestKind* = enum
    tmowrkReqStop
    tmowrkReqSeq
    tmowrkReqPooledSeq

  ThreadtoolsMultiOutputInferenceWorkerRequest* = object
    ## One multi-output inference request.
    kind*: ThreadtoolsMultiOutputInferenceWorkerRequestKind
    requestId*: uint64
    userData*: uint64
    input*: seq[byte]
    pooledInput*: Pooled[seq[byte]]

  ThreadtoolsMultiOutputInferenceWorkerResult* = object
    ## Successful multi-output inference result.
    requestId*: uint64
    userData*: uint64
    inference*: HailoInferenceResult
    poseStats*: Yolov8PoseDecodeStats

  ThreadtoolsMultiOutputInferenceWorkerError* = object
    ## Job-level error payload moved across ThreadQueue.
    status*: hailo_status
    msg*: string

  ThreadtoolsMultiOutputInferenceWorkerReplyKind* = enum
    tmowrkResult
    tmowrkError

  ThreadtoolsMultiOutputInferenceWorkerReply* = object
    ## Reply moved from the worker thread to the caller/control thread.
    kind*: ThreadtoolsMultiOutputInferenceWorkerReplyKind
    requestId*: uint64
    userData*: uint64
    result*: ThreadtoolsMultiOutputInferenceWorkerResult
    error*: ThreadtoolsMultiOutputInferenceWorkerError

  ThreadtoolsMultiOutputInferenceWorkerState = object
    model: MultiOutputInference
    config: ThreadtoolsMultiOutputInferenceWorkerConfig
    requestQ: ThreadQueue[ThreadtoolsMultiOutputInferenceWorkerRequest]
    replyQ: ThreadQueue[ThreadtoolsMultiOutputInferenceWorkerReply]
    outputBuffers: seq[seq[byte]]

  ThreadtoolsMultiOutputInferenceWorker* = ref object
    ## Queue-driven worker for multi-output HEFs.
    ##
    ## The worker owns a MultiOutputInference instance.  It currently executes one
    ## request at a time because MultiOutputInference is synchronous.  This keeps
    ## the ownership and parser path simple for multi-output models such as
    ## yolov8s_pose.  The public submit/waitReply shape matches the single-output
    ## ThreadtoolsInferenceWorker.
    model: MultiOutputInference
    requestQ: ThreadQueue[ThreadtoolsMultiOutputInferenceWorkerRequest]
    replyQ: ThreadQueue[ThreadtoolsMultiOutputInferenceWorkerReply]
    workerThread: Thread[ptr ThreadtoolsMultiOutputInferenceWorkerState]
    state: ThreadtoolsMultiOutputInferenceWorkerState
    config: ThreadtoolsMultiOutputInferenceWorkerConfig
    running: bool
    stopping: bool
    closed: bool

# ==============================================================================
# Lifetime hooks
# ==============================================================================

proc `=destroy`*(self: var ThreadtoolsMultiOutputInferenceWorkerRequest) {.raises: [].} =
  ## Keep requests compatible with std/isolation checks used by ThreadQueue.
  try:
    case self.kind
    of tmowrkReqSeq:
      `=destroy`(self.input)
    of tmowrkReqPooledSeq:
      `=destroy`(self.pooledInput)
    of tmowrkReqStop:
      `=destroy`(self.input)
  except Exception:
    discard

proc clear*(self: var ThreadtoolsMultiOutputInferenceWorkerResult) {.raises: [].} =
  try:
    self.inference.clear()
    self.poseStats = Yolov8PoseDecodeStats()
    self.requestId = 0'u64
    self.userData = 0'u64
  except Exception:
    discard

proc clear*(self: var ThreadtoolsMultiOutputInferenceWorkerError) {.raises: [].} =
  try:
    self.status = HAILO_SUCCESS
    self.msg.setLen(0)
  except Exception:
    discard

proc clear*(self: var ThreadtoolsMultiOutputInferenceWorkerReply) {.raises: [].} =
  ## Explicitly release the active reply payload when the caller wants to reuse
  ## the same reply variable or drop a large result before shutdown.
  ##
  ## The reply is a normal object rather than an object variant, so both result
  ## and error fields physically exist.  Still, only the field selected by kind is
  ## logically active.  Clear only the active side; clearing the inactive side can
  ## touch stale moved-from storage after ThreadQueue ownership transfers.
  try:
    case self.kind
    of tmowrkResult:
      self.result.clear()
    of tmowrkError:
      self.error.clear()

    self.kind = tmowrkError
    self.requestId = 0'u64
    self.userData = 0'u64
  except Exception:
    discard

proc `=destroy`*(self: var ThreadtoolsMultiOutputInferenceWorkerResult) {.raises: [].} =
  ## Keep worker result payloads compatible with std/isolation checks used by
  ## ThreadQueue.  Destruction is best-effort and intentionally no-raise.
  self.clear()

proc `=destroy`*(self: var ThreadtoolsMultiOutputInferenceWorkerError) {.raises: [].} =
  ## Keep worker error payloads compatible with std/isolation checks used by
  ## ThreadQueue.  Destruction is best-effort and intentionally no-raise.
  self.clear()

proc `=destroy`*(self: var ThreadtoolsMultiOutputInferenceWorkerReply) {.raises: [].} =
  ## ThreadQueue.sendMove uses std/isolation, which requires the moved value's
  ## destructor to be known no-raise.  Keep the explicit destructor here even
  ## though clear() should normally be called by the receiver when it is done
  ## with the payload.
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

proc toWorkerError(error: HailoError): ThreadtoolsMultiOutputInferenceWorkerError =
  if error.isNil:
    result.status = HAILO_INVALID_OPERATION
    result.msg = "unknown HAILO error"
  else:
    result.status = error.status
    result.msg = error.msg

proc toHailoError*(error: ThreadtoolsMultiOutputInferenceWorkerError): HailoError =
  result = makeError(error.status, error.msg)

proc makeErrorReply(
  requestId: uint64;
  userData: uint64;
  error: HailoError
): ThreadtoolsMultiOutputInferenceWorkerReply =
  result.kind = tmowrkError
  result.requestId = requestId
  result.userData = userData
  result.error = toWorkerError(error)

proc makeResultReply(
  requestId: uint64;
  userData: uint64;
  inference: sink HailoInferenceResult;
  poseStats: Yolov8PoseDecodeStats
): ThreadtoolsMultiOutputInferenceWorkerReply =
  result.kind = tmowrkResult
  result.requestId = requestId
  result.userData = userData
  result.result = ThreadtoolsMultiOutputInferenceWorkerResult(
    requestId: requestId,
    userData: userData,
    inference: move inference,
    poseStats: poseStats
  )

proc inputLen(req: var ThreadtoolsMultiOutputInferenceWorkerRequest): int {.inline.} =
  case req.kind
  of tmowrkReqStop:
    result = 0
  of tmowrkReqSeq:
    result = req.input.len
  of tmowrkReqPooledSeq:
    if req.pooledInput.isActive:
      result = req.pooledInput.value.len
    else:
      result = 0

proc sendWorkerReply(
  state: ptr ThreadtoolsMultiOutputInferenceWorkerState;
  reply: sink ThreadtoolsMultiOutputInferenceWorkerReply
) =
  var owned = move reply
  discard state.replyQ.sendMove(owned)

proc parseMultiOutputResult(
  state: ptr ThreadtoolsMultiOutputInferenceWorkerState;
  inferResult: MultiOutputInferenceResult;
  requestId: uint64;
  userData: uint64;
  totalUs: int64;
  inference: var HailoInferenceResult;
  poseStats: var Yolov8PoseDecodeStats
): HE[void] =
  let parseStarted = getMonoTime()

  case state.config.parserKind
  of tmopYolov8Pose:
    var poseResult: PoseResult
    let parseRes = parseYolov8PoseInto(
      state.model,
      inferResult,
      state.config.yolov8Pose,
      poseResult,
      poseStats
    )
    let parseUs = elapsedUs(parseStarted)
    if parseRes.isErr:
      return parseRes.error.err

    inference.resetKind(hrkPose)
    inference.setCorrelation(requestId, userData)
    inference.timing = HailoInferenceTiming(
      slotIndex: -1,
      writeUs: inferResult.writeUs,
      readUs: inferResult.readUs,
      parseUs: parseUs,
      sortUs: 0,
      totalUs: totalUs
    )
    inference.pose = move poseResult

  result = okVoid()

proc inferRequestRawInto(
  state: ptr ThreadtoolsMultiOutputInferenceWorkerState;
  req: var ThreadtoolsMultiOutputInferenceWorkerRequest
): HE[MultiOutputInferenceResult] =
  ## Dispatch the request input to MultiOutputInference without trying to return
  ## openArray[byte].  Nim's openArray is a parameter-only view type, so it cannot
  ## be used as a proc return type.
  case req.kind
  of tmowrkReqStop:
    result = makeError(
      HAILO_INVALID_OPERATION,
      "stop request does not contain inference input"
    ).err
  of tmowrkReqSeq:
    result = state.model.inferRawInto(req.input, state.outputBuffers)
  of tmowrkReqPooledSeq:
    result = state.model.inferRawInto(req.pooledInput.value, state.outputBuffers)

proc handleRequest(
  state: ptr ThreadtoolsMultiOutputInferenceWorkerState;
  req: sink ThreadtoolsMultiOutputInferenceWorkerRequest
): bool =
  ## Returns false when the worker should exit.
  var ownedReq = move req

  if ownedReq.kind == tmowrkReqStop:
    return false

  if ownedReq.inputLen() == 0:
    var reply = makeErrorReply(
      ownedReq.requestId,
      ownedReq.userData,
      makeError(HAILO_INVALID_ARGUMENT, "multi-output worker request input is empty")
    )
    state.sendWorkerReply(move reply)
    return true

  let started = getMonoTime()
  let inferRes = state.inferRequestRawInto(ownedReq)
  let totalAfterInferUs = elapsedUs(started)

  if inferRes.isErr:
    var reply = makeErrorReply(ownedReq.requestId, ownedReq.userData, inferRes.error)
    state.sendWorkerReply(move reply)
    return true

  let inferResult = inferRes.get()
  var inference: HailoInferenceResult
  var poseStats: Yolov8PoseDecodeStats
  let parseRes = state.parseMultiOutputResult(
    inferResult,
    ownedReq.requestId,
    ownedReq.userData,
    totalAfterInferUs,
    inference,
    poseStats
  )

  if parseRes.isErr:
    var reply = makeErrorReply(ownedReq.requestId, ownedReq.userData, parseRes.error)
    state.sendWorkerReply(move reply)
    return true

  var reply = makeResultReply(
    ownedReq.requestId,
    ownedReq.userData,
    move inference,
    poseStats
  )
  state.sendWorkerReply(move reply)
  result = true

proc releaseOutputBuffersOnWorkerThread(
  state: ptr ThreadtoolsMultiOutputInferenceWorkerState
) {.raises: [].} =
  ## outputBuffers is resized and filled on the worker thread.  With Nim's
  ## per-thread allocator/ORC behavior, those GC-managed seq buffers should also
  ## be released on the worker thread.  Releasing them later from the owner
  ## thread during join()/close() can corrupt allocator state on musl/aarch64.
  try:
    state.outputBuffers = @[]
  except Exception:
    discard

proc multiOutputInferenceWorkerMain(state: ptr ThreadtoolsMultiOutputInferenceWorkerState) {.thread.} =
  try:
    while true:
      var reqRes = state.requestQ.receiveResult()
      if reqRes.isErr:
        break

      var req = reqRes.take()
      let keepRunning = state.handleRequest(move req)
      if not keepRunning:
        break
  finally:
    state.releaseOutputBuffersOnWorkerThread()

# ==============================================================================
# Configuration
# ==============================================================================

proc recommendedThreadtoolsMultiOutputInferenceWorkerRequestQueueSize*(slotCount: int): int =
  ## MultiOutputInference is synchronous today, but keep the same queue sizing
  ## convention as the single-output worker for caller-side loops.
  if slotCount <= 0:
    return 2
  result = max(2, slotCount * 2)

proc initThreadtoolsYolov8PoseWorkerConfig*(
  slotCount = 1;
  poseConfig: Yolov8PoseParserConfig = initYolov8PoseParserConfig()
): ThreadtoolsMultiOutputInferenceWorkerConfig =
  let requestQueueSize = recommendedThreadtoolsMultiOutputInferenceWorkerRequestQueueSize(slotCount)
  result = ThreadtoolsMultiOutputInferenceWorkerConfig(
    requestQueueSize: requestQueueSize,
    replyQueueSize: requestQueueSize + 1,
    parserKind: tmopYolov8Pose,
    yolov8Pose: poseConfig
  )

proc validateConfig(config: ThreadtoolsMultiOutputInferenceWorkerConfig): HE[void] =
  if config.requestQueueSize <= 0:
    return makeError(HAILO_INVALID_ARGUMENT, "requestQueueSize must be positive").err

  if config.replyQueueSize <= 0:
    return makeError(HAILO_INVALID_ARGUMENT, "replyQueueSize must be positive").err

  if config.replyQueueSize < config.requestQueueSize + 1:
    return makeError(
      HAILO_INVALID_ARGUMENT,
      &"replyQueueSize must be >= requestQueueSize + 1: replyQueueSize={config.replyQueueSize} requestQueueSize={config.requestQueueSize}"
    ).err

  if config.parserKind == tmopYolov8Pose:
    let pc = config.yolov8Pose
    if pc.inputWidth <= 0 or pc.inputHeight <= 0:
      return makeError(HAILO_INVALID_ARGUMENT, "YOLOv8 pose input size must be positive").err
    if pc.candidateLimit <= 0:
      return makeError(HAILO_INVALID_ARGUMENT, "YOLOv8 pose candidateLimit must be positive").err
    if pc.maxPoses <= 0:
      return makeError(HAILO_INVALID_ARGUMENT, "YOLOv8 pose maxPoses must be positive").err

  result = okVoid()

# ==============================================================================
# Construction / teardown
# ==============================================================================

proc startThreadtoolsMultiOutputInferenceWorker*(
  model: MultiOutputInference;
  config: ThreadtoolsMultiOutputInferenceWorkerConfig
): HE[ThreadtoolsMultiOutputInferenceWorker] =
  ## Start a queue-driven multi-output inference worker.
  ##
  ## Ownership note: after this succeeds, the worker owns model.  Do not call
  ## model.inferRaw*/close() directly.  close(worker) sends a stop request, joins
  ## the thread, and closes model on the owner thread.
  if model.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "multi-output inference model is nil").err

  if not model.isActivated():
    return makeError(HAILO_INVALID_OPERATION, "multi-output inference model is not activated").err

  if config.parserKind == tmopYolov8Pose and
      model.requestedOutputFormatType() != HAILO_FORMAT_TYPE_FLOAT32:
    return makeError(
      HAILO_INVALID_OPERATION,
      "YOLOv8 pose worker requires MultiOutputInference opened with outputFormatType=HAILO_FORMAT_TYPE_FLOAT32"
    ).err

  let configRes = validateConfig(config)
  if configRes.isErr:
    return configRes.error.err

  var requestQRes = newThreadQueue[ThreadtoolsMultiOutputInferenceWorkerRequest](
    config.requestQueueSize
  )
  if requestQRes.isErr:
    return threadtoolsError(requestQRes.error, "new multi-output worker request queue").err

  var replyQRes = newThreadQueue[ThreadtoolsMultiOutputInferenceWorkerReply](
    config.replyQueueSize
  )
  if replyQRes.isErr:
    return threadtoolsError(replyQRes.error, "new multi-output worker reply queue").err

  var w = ThreadtoolsMultiOutputInferenceWorker()
  w.model = model
  w.requestQ = requestQRes.get()
  w.replyQ = replyQRes.get()
  w.config = config
  w.state.model = model
  w.state.config = config
  w.state.requestQ = w.requestQ
  w.state.replyQ = w.replyQ
  w.state.outputBuffers = @[]

  createThread(w.workerThread, multiOutputInferenceWorkerMain, addr w.state)
  w.running = true

  result = w.ok

proc stop*(w: ThreadtoolsMultiOutputInferenceWorker): HE[void] =
  if w.isNil:
    return okVoid()

  if w.closed or not w.running or w.stopping:
    return okVoid()

  if w.requestQ.isNil:
    return makeError(HAILO_INVALID_OPERATION, "multi-output worker request queue is nil").err

  var stopReq = ThreadtoolsMultiOutputInferenceWorkerRequest(
    kind: tmowrkReqStop,
    requestId: 0'u64,
    userData: 0'u64,
    input: @[]
  )
  let sendRes = w.requestQ.sendMove(stopReq)
  if sendRes.isErr:
    return threadtoolsError(sendRes.error, "send multi-output worker stop request").err

  w.stopping = true
  result = okVoid()

proc join*(w: ThreadtoolsMultiOutputInferenceWorker): HE[void] =
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

  if not w.model.isNil:
    let closeRes = w.model.close()
    if closeRes.isErr:
      return closeRes.error.err

  if not w.requestQ.isNil:
    w.requestQ.close()
  if not w.replyQ.isNil:
    w.replyQ.close()

  w.model = nil
  w.state.model = nil
  # state.outputBuffers is owned and released by the worker thread before
  # joinThread() returns.  Do not clear it here from the caller thread.
  w.requestQ = nil
  w.replyQ = nil
  w.state.requestQ = nil
  w.state.replyQ = nil
  w.closed = true

  result = okVoid()

proc close*(w: ThreadtoolsMultiOutputInferenceWorker): HE[void] =
  result = w.join()

# ==============================================================================
# Introspection
# ==============================================================================

proc config*(w: ThreadtoolsMultiOutputInferenceWorker): ThreadtoolsMultiOutputInferenceWorkerConfig =
  if w.isNil:
    return initThreadtoolsYolov8PoseWorkerConfig()
  result = w.config

proc isRunning*(w: ThreadtoolsMultiOutputInferenceWorker): bool =
  if w.isNil:
    return false
  result = w.running

proc isStopping*(w: ThreadtoolsMultiOutputInferenceWorker): bool =
  if w.isNil:
    return false
  result = w.stopping

proc isClosed*(w: ThreadtoolsMultiOutputInferenceWorker): bool =
  if w.isNil:
    return true
  result = w.closed

proc inputSize*(w: ThreadtoolsMultiOutputInferenceWorker): int =
  if w.isNil or w.model.isNil:
    return 0
  result = w.model.inputSize()

proc outputCount*(w: ThreadtoolsMultiOutputInferenceWorker): int =
  if w.isNil or w.model.isNil:
    return 0
  result = w.model.outputCount()

proc profileSummary*(w: ThreadtoolsMultiOutputInferenceWorker): string =
  if w.isNil or w.model.isNil:
    return "hailort_multi_output_profile model=nil"
  result = w.model.profileSummary()

proc outputMetadata*(w: ThreadtoolsMultiOutputInferenceWorker; index: int): HE[VStreamMetadata] =
  if w.isNil or w.model.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "multi-output worker model is nil").err
  result = w.model.outputMetadata(index)

proc outputMetadatas*(w: ThreadtoolsMultiOutputInferenceWorker): HE[seq[VStreamMetadata]] =
  if w.isNil or w.model.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "multi-output worker model is nil").err
  result = w.model.outputMetadatas()

# ==============================================================================
# Submit / receive
# ==============================================================================

proc submit*(
  w: ThreadtoolsMultiOutputInferenceWorker;
  input: sink seq[byte];
  requestId: uint64 = 0'u64;
  userData: uint64 = 0'u64
): HE[void] =
  if w.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "multi-output worker is nil").err

  if w.closed:
    return makeError(HAILO_INVALID_OPERATION, "multi-output worker is closed").err

  if w.stopping:
    return makeError(HAILO_INVALID_OPERATION, "multi-output worker is stopping").err

  if not w.running:
    return makeError(HAILO_INVALID_OPERATION, "multi-output worker is not running").err

  if input.len == 0:
    return makeError(HAILO_INVALID_ARGUMENT, "input is empty").err

  if w.inputSize() > 0 and input.len != w.inputSize():
    return makeError(
      HAILO_INVALID_ARGUMENT,
      &"input size mismatch: expected={w.inputSize()} actual={input.len}"
    ).err

  var req = ThreadtoolsMultiOutputInferenceWorkerRequest(
    kind: tmowrkReqSeq,
    requestId: requestId,
    userData: userData,
    input: move input
  )
  let sendRes = w.requestQ.sendMove(req)
  if sendRes.isErr:
    return threadtoolsError(sendRes.error, "send multi-output worker request").err

  result = okVoid()

proc submitPooled*(
  w: ThreadtoolsMultiOutputInferenceWorker;
  input: sink Pooled[seq[byte]];
  requestId: uint64 = 0'u64;
  userData: uint64 = 0'u64
): HE[void] =
  if w.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "multi-output worker is nil").err

  if w.closed:
    return makeError(HAILO_INVALID_OPERATION, "multi-output worker is closed").err

  if w.stopping:
    return makeError(HAILO_INVALID_OPERATION, "multi-output worker is stopping").err

  if not w.running:
    return makeError(HAILO_INVALID_OPERATION, "multi-output worker is not running").err

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

  var req = ThreadtoolsMultiOutputInferenceWorkerRequest(
    kind: tmowrkReqPooledSeq,
    requestId: requestId,
    userData: userData,
    pooledInput: move ownedInput
  )
  let sendRes = w.requestQ.sendMove(req)
  if sendRes.isErr:
    return threadtoolsError(sendRes.error, "send multi-output worker pooled request").err

  result = okVoid()

proc submitPoolItem*(
  w: ThreadtoolsMultiOutputInferenceWorker;
  input: sink Pooled[seq[byte]];
  requestId: uint64 = 0'u64;
  userData: uint64 = 0'u64
): HE[void] {.inline.} =
  result = w.submitPooled(move input, requestId, userData)

proc submitCopy*(
  w: ThreadtoolsMultiOutputInferenceWorker;
  input: openArray[byte];
  requestId: uint64 = 0'u64;
  userData: uint64 = 0'u64
): HE[void] =
  var owned = newSeq[byte](input.len)
  if input.len > 0:
    copyMem(addr owned[0], unsafeAddr input[0], input.len)
  result = w.submit(move owned, requestId, userData)

proc waitReply*(
  w: ThreadtoolsMultiOutputInferenceWorker;
  reply: var ThreadtoolsMultiOutputInferenceWorkerReply
): HE[void] =
  if w.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "multi-output worker is nil").err

  if w.closed:
    return makeError(HAILO_INVALID_OPERATION, "multi-output worker is closed").err

  var recvRes = w.replyQ.receiveResult()
  if recvRes.isErr:
    return threadtoolsError(recvRes.error, "receive multi-output worker reply").err

  var tmp = recvRes.take()
  reply = move tmp
  result = okVoid()

proc recv*(
  w: ThreadtoolsMultiOutputInferenceWorker;
  reply: var ThreadtoolsMultiOutputInferenceWorkerReply
): HE[void] {.inline.} =
  result = w.waitReply(reply)

proc tryWaitReply*(
  w: ThreadtoolsMultiOutputInferenceWorker;
  reply: var ThreadtoolsMultiOutputInferenceWorkerReply
): HE[bool] =
  if w.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "multi-output worker is nil").err

  if w.closed:
    return makeError(HAILO_INVALID_OPERATION, "multi-output worker is closed").err

  var tmp: ThreadtoolsMultiOutputInferenceWorkerReply
  let recvRes = w.replyQ.tryReceive(tmp)
  if recvRes.isErr:
    return threadtoolsError(recvRes.error, "try receive multi-output worker reply").err

  if not recvRes.get():
    return false.ok

  reply = move tmp
  result = true.ok

proc tryRecv*(
  w: ThreadtoolsMultiOutputInferenceWorker;
  reply: var ThreadtoolsMultiOutputInferenceWorkerReply
): HE[bool] {.inline.} =
  result = w.tryWaitReply(reply)
