when not compileOption("threads"):
  {.error: "threadtools_detector_worker requires --threads:on".}

import std/[monotimes, strformat, times]

import threadtools

import ./detector
import ./threadtools_detector
import ./threadtools_vstream_runner
import ../models/detection
import ../bindings/c_api
import ../internal/error

# ==============================================================================
# Public types
# ==============================================================================

type
  ThreadtoolsDetectorWorkerConfig* = object
    ## Queue configuration for a full detector worker.
    ##
    ## The worker owns a ThreadtoolsDetector and executes submit + waitDetections
    ## on its worker thread.  Input buffers are moved to the worker through a
    ## ThreadQueue as seq[byte].  Detection replies are moved back through another
    ## ThreadQueue.
    requestQueueSize*: int
    replyQueueSize*: int

  ThreadtoolsDetectorWorkerRequest* = object
    ## One inference request for ThreadtoolsDetectorWorker.
    ##
    ## input is owned by the request.  Prefer submit(move input) for already
    ## owned seq[byte] buffers.  submitCopy() is provided for openArray callers.
    ##
    ## requestId and userData are opaque caller-supplied correlation fields.
    ## Both are copied to the reply, including error replies.
    requestId*: uint64
    userData*: uint64
    input*: seq[byte]
    appScoreThreshold*: float32

  ThreadtoolsDetectorWorkerResult* = object
    ## Successful inference result returned by ThreadtoolsDetectorWorker.
    requestId*: uint64
    userData*: uint64
    timing*: ThreadtoolsDetectionResult
    detections*: seq[Detection]

  ThreadtoolsDetectorWorkerError* = object
    ## Job-level error payload that is safe to move across ThreadQueue.
    ##
    ## HailoError itself is a ref object, so worker replies carry only copyable /
    ## movable status+message data.  Convert it back with toHailoError() if a
    ## normal HE-style error is needed.
    status*: hailo_status
    msg*: string

  ThreadtoolsDetectorWorkerReplyKind* = enum
    tdwrkResult
    tdwrkError

  ThreadtoolsDetectorWorkerReply* = object
    ## Reply moved from the detector worker to the caller/control thread.
    ##
    ## Job-level HAILO errors are reported as tdwrkError replies so the caller
    ## can keep requestId/userData association.  Queue/worker state errors are returned
    ## from waitReply()/tryWaitReply() as HE errors.
    kind*: ThreadtoolsDetectorWorkerReplyKind
    requestId*: uint64
    userData*: uint64
    result*: ThreadtoolsDetectorWorkerResult
    error*: ThreadtoolsDetectorWorkerError

  ThreadtoolsDetectorWorkerState = object
    detector: ThreadtoolsDetector
    requestQ: ThreadQueue[ThreadtoolsDetectorWorkerRequest]
    replyQ: ThreadQueue[ThreadtoolsDetectorWorkerReply]

  ThreadtoolsDetectorWorker* = ref object
    ## Worker handle for queue-driven HAILO object detection.
    ##
    ## This is the first application/pipeline-facing API: callers submit owned
    ## input buffers to requestQ and receive replies from replyQ.  The worker owns
    ## the ThreadtoolsDetector until close() returns.
    ##
    ## The detector is used by the worker thread, but close() is executed on the
    ## owner thread after the worker has joined.  This avoids manipulating Nim ref
    ## fields from the worker during shutdown.
    detector: ThreadtoolsDetector
    requestQ: ThreadQueue[ThreadtoolsDetectorWorkerRequest]
    replyQ: ThreadQueue[ThreadtoolsDetectorWorkerReply]
    workerThread: Thread[ptr ThreadtoolsDetectorWorkerState]
    state: ThreadtoolsDetectorWorkerState
    config: ThreadtoolsDetectorWorkerConfig
    running: bool
    stopping: bool
    closed: bool

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

proc toWorkerError(error: HailoError): ThreadtoolsDetectorWorkerError =
  if error.isNil:
    result.status = HAILO_INVALID_OPERATION
    result.msg = "unknown HAILO error"
  else:
    result.status = error.status
    result.msg = error.msg

proc toHailoError*(error: ThreadtoolsDetectorWorkerError): HailoError =
  result = makeError(error.status, error.msg)

proc makeErrorReply(
  requestId: uint64;
  userData: uint64;
  error: HailoError
): ThreadtoolsDetectorWorkerReply =
  result.kind = tdwrkError
  result.requestId = requestId
  result.userData = userData
  result.error = toWorkerError(error)

proc makeResultReply(
  requestId: uint64;
  userData: uint64;
  timing: ThreadtoolsDetectionResult;
  detections: sink seq[Detection]
): ThreadtoolsDetectorWorkerReply =
  result.kind = tdwrkResult
  result.requestId = requestId
  result.userData = userData
  result.result = ThreadtoolsDetectorWorkerResult(
    requestId: requestId,
    userData: userData,
    timing: timing,
    detections: move detections
  )

# ==============================================================================
# Worker main
# ==============================================================================

type
  PendingRequest = object
    requestId: uint64
    userData: uint64
    appScoreThreshold: float32

proc sendWorkerReply(
  state: ptr ThreadtoolsDetectorWorkerState;
  reply: sink ThreadtoolsDetectorWorkerReply
) =
  var owned = move reply
  discard state.replyQ.sendMove(owned)

proc handleSubmitRequest(
  state: ptr ThreadtoolsDetectorWorkerState;
  req: sink ThreadtoolsDetectorWorkerRequest;
  pending: var seq[PendingRequest]
): bool =
  ## Returns false when the worker should stop accepting new requests.
  var ownedReq = move req

  if ownedReq.input.len == 0:
    return false

  let submitRes = state.detector.submit(ownedReq.input)
  if submitRes.isErr:
    var reply = makeErrorReply(ownedReq.requestId, ownedReq.userData, submitRes.error)
    state.sendWorkerReply(move reply)
    return true

  pending.add PendingRequest(
    requestId: ownedReq.requestId,
    userData: ownedReq.userData,
    appScoreThreshold: ownedReq.appScoreThreshold
  )
  result = true

proc receiveBlockingRequest(
  state: ptr ThreadtoolsDetectorWorkerState;
  pending: var seq[PendingRequest]
): bool =
  ## Blocks until one request is available.  Returns false on stop/queue error.
  var reqRes = state.requestQ.receiveResult()
  if reqRes.isErr:
    return false

  var req = reqRes.take()
  result = state.handleSubmitRequest(move req, pending)

proc tryReceiveRequest(
  state: ptr ThreadtoolsDetectorWorkerState;
  pending: var seq[PendingRequest]
): bool =
  ## Attempts to receive one request without blocking.
  ##
  ## Returns false when no request is available or when stop/queue close is seen.
  ## The caller distinguishes the stop state through the request queue state only
  ## loosely; this worker treats closed queues as a shutdown request.
  var req: ThreadtoolsDetectorWorkerRequest
  let recvRes = state.requestQ.tryReceive(req)
  if recvRes.isErr:
    return false

  if not recvRes.get():
    return false

  result = state.handleSubmitRequest(move req, pending)

proc detectorWorkerMain(state: ptr ThreadtoolsDetectorWorkerState) {.thread.} =
  ## Pipelined detector worker.
  ##
  ## Step 4 originally used detectOnce() per request.  That serialized
  ## write/read/parse and prevented ThreadtoolsVStreamRunner's output slots from
  ## overlapping.  This loop keeps up to slotCount submissions in flight:
  ##
  ##   requestQ -> submit() while slots are available
  ##            -> waitDetections() for oldest pending request
  ##            -> replyQ
  ##
  ## Stop requests stop accepting new input, but already-submitted requests are
  ## drained before the thread exits.
  var pending: seq[PendingRequest] = @[]
  var accepting = true

  while true:
    while accepting and pending.len < state.detector.slotCount():
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

    var detections: seq[Detection] = @[]
    let pendingReq = pending[0]
    let started = getMonoTime()
    let detectRes = state.detector.waitDetections(
      detections,
      pendingReq.appScoreThreshold
    )
    let totalUs = elapsedUs(started)
    pending.delete(0)

    if detectRes.isErr:
      var reply = makeErrorReply(pendingReq.requestId, pendingReq.userData, detectRes.error)
      state.sendWorkerReply(move reply)
      continue

    var timing = detectRes.get()
    ## ThreadtoolsDetectionResult intentionally keeps per-stage timing.  The
    ## full worker wait time is not added to that object yet to keep Step 4
    ## compatible with the Step 3 result shape.
    discard totalUs

    var reply = makeResultReply(
      pendingReq.requestId,
      pendingReq.userData,
      timing,
      move detections
    )
    state.sendWorkerReply(move reply)

# ==============================================================================
# Configuration
# ==============================================================================

proc recommendedThreadtoolsDetectorWorkerRequestQueueSize*(slotCount: int): int =
  ## Recommended request queue depth for benchmark-style single-threaded
  ## submit/recv loops.
  ##
  ## A detector worker can keep up to slotCount HAILO requests in flight.  If the
  ## caller submits the next request only after receiving a reply, a request
  ## queue equal to slotCount can become empty at the exact moment the worker
  ## tries to refill a slot.  Keeping at least another slotCount requests queued
  ## avoids that saw-tooth underfill.
  if slotCount <= 0:
    return 2

  result = max(2, slotCount * 2)

proc defaultThreadtoolsDetectorWorkerConfig*(slotCount = 2): ThreadtoolsDetectorWorkerConfig =
  let requestQueueSize = recommendedThreadtoolsDetectorWorkerRequestQueueSize(slotCount)
  result = ThreadtoolsDetectorWorkerConfig(
    requestQueueSize: requestQueueSize,
    replyQueueSize: requestQueueSize + 1
  )

proc validateConfig(config: ThreadtoolsDetectorWorkerConfig): HE[void] =
  if config.requestQueueSize <= 0:
    return makeError(HAILO_INVALID_ARGUMENT, "requestQueueSize must be positive").err

  if config.replyQueueSize <= 0:
    return makeError(HAILO_INVALID_ARGUMENT, "replyQueueSize must be positive").err

  if config.replyQueueSize < config.requestQueueSize + 1:
    return makeError(
      HAILO_INVALID_ARGUMENT,
      &"replyQueueSize must be >= requestQueueSize + 1: replyQueueSize={config.replyQueueSize} requestQueueSize={config.requestQueueSize}"
    ).err

  result = okVoid()

# ==============================================================================
# Construction / teardown
# ==============================================================================

proc startThreadtoolsDetectorWorker*(
  td: ThreadtoolsDetector;
  config: ThreadtoolsDetectorWorkerConfig
): HE[ThreadtoolsDetectorWorker] =
  ## Start a queue-driven detector worker.
  ##
  ## Ownership note: after this succeeds, the worker owns td.  Do not call td
  ## directly or close it separately.  close(worker) sends the stop request,
  ## joins the worker thread, and then closes td on the owner thread.
  if td.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "threadtools detector is nil").err

  if not td.isRunning():
    return makeError(HAILO_INVALID_OPERATION, "threadtools detector is not running").err

  let configRes = validateConfig(config)
  if configRes.isErr:
    return configRes.error.err

  var requestQRes = newThreadQueue[ThreadtoolsDetectorWorkerRequest](
    config.requestQueueSize
  )
  if requestQRes.isErr:
    return threadtoolsError(requestQRes.error, "new detector worker request queue").err

  var replyQRes = newThreadQueue[ThreadtoolsDetectorWorkerReply](
    config.replyQueueSize
  )
  if replyQRes.isErr:
    return threadtoolsError(replyQRes.error, "new detector worker reply queue").err

  var w = ThreadtoolsDetectorWorker()
  w.detector = td
  w.requestQ = requestQRes.get()
  w.replyQ = replyQRes.get()
  w.config = config
  w.state.detector = td
  w.state.requestQ = w.requestQ
  w.state.replyQ = w.replyQ

  createThread(w.workerThread, detectorWorkerMain, addr w.state)
  w.running = true

  result = w.ok

proc startThreadtoolsDetectorWorker*(
  td: ThreadtoolsDetector
): HE[ThreadtoolsDetectorWorker] =
  result = td.startThreadtoolsDetectorWorker(
    defaultThreadtoolsDetectorWorkerConfig()
  )

proc startThreadtoolsDetectorWorker*(
  d: Detector;
  runnerConfig: ThreadtoolsVStreamRunnerConfig;
  workerConfig: ThreadtoolsDetectorWorkerConfig
): HE[ThreadtoolsDetectorWorker] =
  ## Build a ThreadtoolsDetector from an activated Detector and start a worker.
  let tdRes = d.openThreadtoolsDetector(runnerConfig)
  if tdRes.isErr:
    return tdRes.error.err

  let td = tdRes.get()
  let workerRes = td.startThreadtoolsDetectorWorker(workerConfig)
  if workerRes.isErr:
    discard td.close()
    return workerRes.error.err

  result = workerRes

proc startThreadtoolsDetectorWorker*(
  d: Detector;
  slotCount = 2;
  requestQueueSize = 0
): HE[ThreadtoolsDetectorWorker] =
  var runnerConfig = defaultThreadtoolsVStreamRunnerConfig()
  runnerConfig.slotCount = slotCount
  runnerConfig.inputQueueSize = slotCount
  runnerConfig.resultQueueSize = slotCount

  let effectiveRequestQueueSize =
    if requestQueueSize > 0:
      requestQueueSize
    else:
      recommendedThreadtoolsDetectorWorkerRequestQueueSize(slotCount)

  var workerConfig = defaultThreadtoolsDetectorWorkerConfig(slotCount)
  workerConfig.requestQueueSize = effectiveRequestQueueSize
  workerConfig.replyQueueSize = effectiveRequestQueueSize + 1

  result = d.startThreadtoolsDetectorWorker(runnerConfig, workerConfig)

proc stop*(w: ThreadtoolsDetectorWorker): HE[void] =
  ## Request a graceful worker stop.
  ##
  ## stop() is idempotent.  It tells the worker to stop accepting new requests.
  ## Requests already submitted to HAILO are drained before the worker thread exits.
  ##
  ## After stop(), callers may keep receiving the replies they expect, then call
  ## join().  close() is equivalent to stop() + join() and is convenient when the
  ## caller does not need to drain remaining replies.
  if w.isNil:
    return okVoid()

  if w.closed or not w.running or w.stopping:
    return okVoid()

  if w.requestQ.isNil:
    return makeError(HAILO_INVALID_OPERATION, "detector worker request queue is nil").err

  var stopReq = ThreadtoolsDetectorWorkerRequest(
    requestId: 0'u64,
    userData: 0'u64,
    input: @[],
    appScoreThreshold: 0.0'f32
  )
  let sendRes = w.requestQ.sendMove(stopReq)
  if sendRes.isErr:
    return threadtoolsError(sendRes.error, "send detector worker stop request").err

  w.stopping = true
  result = okVoid()

proc join*(w: ThreadtoolsDetectorWorker): HE[void] =
  ## Wait for the detector worker to exit and release its owned resources.
  ##
  ## If stop() was not called yet, join() requests stop first.  The underlying
  ## ThreadtoolsDetector is closed on the owner thread after the worker has
  ## terminated.  The reply queue is then closed, so callers that need all replies
  ## should drain them before calling join().
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

  if not w.detector.isNil:
    let closeRes = w.detector.close()
    if closeRes.isErr:
      return closeRes.error.err

  if not w.requestQ.isNil:
    w.requestQ.close()
  if not w.replyQ.isNil:
    w.replyQ.close()

  w.detector = nil
  w.state.detector = nil
  w.requestQ = nil
  w.replyQ = nil
  w.state.requestQ = nil
  w.state.replyQ = nil
  w.closed = true

  result = okVoid()

proc close*(w: ThreadtoolsDetectorWorker): HE[void] =
  ## Stop and join the detector worker.
  ##
  ## This is the normal RAII-style teardown helper.  Use stop() and join()
  ## separately when the application wants to drain known outstanding replies
  ## before closing the reply queue.
  result = w.join()

# ==============================================================================
# Introspection
# ==============================================================================

proc config*(w: ThreadtoolsDetectorWorker): ThreadtoolsDetectorWorkerConfig =
  if w.isNil:
    return defaultThreadtoolsDetectorWorkerConfig()

  result = w.config

proc isRunning*(w: ThreadtoolsDetectorWorker): bool =
  if w.isNil:
    return false

  result = w.running

proc isStopping*(w: ThreadtoolsDetectorWorker): bool =
  if w.isNil:
    return false

  result = w.stopping

proc isClosed*(w: ThreadtoolsDetectorWorker): bool =
  if w.isNil:
    return true

  result = w.closed

proc inputSize*(w: ThreadtoolsDetectorWorker): int =
  if w.isNil or w.detector.isNil:
    return 0

  result = w.detector.inputSize()

proc outputSize*(w: ThreadtoolsDetectorWorker): int =
  if w.isNil or w.detector.isNil:
    return 0

  result = w.detector.outputSize()

# ==============================================================================
# Submit / receive
# ==============================================================================

proc submit*(
  w: ThreadtoolsDetectorWorker;
  input: sink seq[byte];
  requestId: uint64 = 0'u64;
  appScoreThreshold = 0.25'f32;
  userData: uint64 = 0'u64
): HE[void] =
  ## Submit an owned seq[byte] input buffer to the detector worker.
  ##
  ## Use submit(worker, move input) when the caller owns a reusable frame buffer
  ## and wants to transfer it without copying.  The worker releases the seq after
  ## detection finishes.  For borrowed openArray data, use submitCopy().
  if w.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "detector worker is nil").err

  if w.closed:
    return makeError(HAILO_INVALID_OPERATION, "detector worker is closed").err

  if w.stopping:
    return makeError(HAILO_INVALID_OPERATION, "detector worker is stopping").err

  if not w.running:
    return makeError(HAILO_INVALID_OPERATION, "detector worker is not running").err

  if input.len == 0:
    return makeError(HAILO_INVALID_ARGUMENT, "input is empty").err

  if w.inputSize() > 0 and input.len != w.inputSize():
    return makeError(
      HAILO_INVALID_ARGUMENT,
      &"input size mismatch: expected={w.inputSize()} actual={input.len}"
    ).err

  var req = ThreadtoolsDetectorWorkerRequest(
    requestId: requestId,
    userData: userData,
    input: move input,
    appScoreThreshold: appScoreThreshold
  )
  let sendRes = w.requestQ.sendMove(req)
  if sendRes.isErr:
    return threadtoolsError(sendRes.error, "send detector worker request").err

  result = okVoid()

proc submitCopy*(
  w: ThreadtoolsDetectorWorker;
  input: openArray[byte];
  requestId: uint64 = 0'u64;
  appScoreThreshold = 0.25'f32;
  userData: uint64 = 0'u64
): HE[void] =
  ## Submit a borrowed input buffer by copying it into an owned seq[byte].
  ##
  ## This is convenient for tests and existing high-level code.  Streaming
  ## pipelines should prefer submit(move seqBuf) or a future PoolItem-based API.
  var owned = newSeq[byte](input.len)
  if input.len > 0:
    copyMem(addr owned[0], unsafeAddr input[0], input.len)

  result = w.submit(move owned, requestId, appScoreThreshold, userData)

proc waitReply*(
  w: ThreadtoolsDetectorWorker;
  reply: var ThreadtoolsDetectorWorkerReply
): HE[void] =
  ## Blocking receive of one worker reply.
  ##
  ## The reply is moved into caller-provided storage to avoid wrapping a large
  ## seq[Detection] in Result[T, E] and extracting it with .get().
  if w.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "detector worker is nil").err

  if w.closed:
    return makeError(HAILO_INVALID_OPERATION, "detector worker is closed").err

  var recvRes = w.replyQ.receiveResult()
  if recvRes.isErr:
    return threadtoolsError(recvRes.error, "receive detector worker reply").err

  var tmp = recvRes.take()
  reply = move tmp
  result = okVoid()

proc recv*(
  w: ThreadtoolsDetectorWorker;
  reply: var ThreadtoolsDetectorWorkerReply
): HE[void] {.inline.} =
  result = w.waitReply(reply)

proc tryWaitReply*(
  w: ThreadtoolsDetectorWorker;
  reply: var ThreadtoolsDetectorWorkerReply
): HE[bool] =
  ## Non-blocking receive of one worker reply.
  if w.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "detector worker is nil").err

  if w.closed:
    return makeError(HAILO_INVALID_OPERATION, "detector worker is closed").err

  var tmp: ThreadtoolsDetectorWorkerReply
  let recvRes = w.replyQ.tryReceive(tmp)
  if recvRes.isErr:
    return threadtoolsError(recvRes.error, "try receive detector worker reply").err

  if not recvRes.get():
    return false.ok

  reply = move tmp
  result = true.ok

proc tryRecv*(
  w: ThreadtoolsDetectorWorker;
  reply: var ThreadtoolsDetectorWorkerReply
): HE[bool] {.inline.} =
  result = w.tryWaitReply(reply)
