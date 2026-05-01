when not compileOption("threads"):
  {.error: "async_detector requires --threads:on".}

import std/[monotimes, strformat, times]

import ./detector
import ./async_vstream_runner
import ../lowlevel
import ../models/detection
import ../bindings/types
import ../internal/error

type
  AsyncDetectionResult* = object
    ## Result metadata for one completed async detection.
    ##
    ## Detections themselves are written into the caller-provided seq.
    slotIndex*: int
    writeUs*: int64
    readUs*: int64
    parseUs*: int64
    sortUs*: int64
    detectionCount*: int

  AsyncDetector* = ref object
    ## Async-style object detector built on top of AsyncVStreamRunner.
    ##
    ## This is still YOLO/NMS-by-class specific.  The generic vstream overlap
    ## logic lives in AsyncVStreamRunner; this layer only parses the model output
    ## into seq[Detection].
    ##
    ## The source Detector must stay alive and activated until close() returns.
    detector: Detector
    runner: AsyncVStreamRunner

# ------------------------------------------------------------------------------
#
# elapsedUs:
#
# ------------------------------------------------------------------------------

proc elapsedUs(started: MonoTime): int64 {.inline.} =
  result = inMicroseconds(getMonoTime() - started)

# ------------------------------------------------------------------------------
#
# validateDetector:
#
# ------------------------------------------------------------------------------

proc validateDetector(d: Detector): HE[void] =
  if d.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "detector is nil").err

  if not d.isActivated():
    return makeError(HAILO_INVALID_OPERATION, "detector is not activated").err

  if d.outputInfo.format.order != HAILO_FORMAT_ORDER_HAILO_NMS_BY_CLASS:
    return makeError(
      HAILO_INVALID_OPERATION,
      &"output format is not HAILO_FORMAT_ORDER_HAILO_NMS_BY_CLASS: got {ord(d.outputInfo.format.order)}"
    ).err

  result = okVoid()

# ------------------------------------------------------------------------------
#
# parseOutputInto:
#
# ------------------------------------------------------------------------------

proc parseOutputInto(
  ad: AsyncDetector;
  res: AsyncVStreamResult;
  detections: var seq[Detection];
  appScoreThreshold: float32
): HE[tuple[parseUs, sortUs: int64]] =
  if ad.isNil or ad.detector.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "async detector is nil").err

  if res.outputPtr.isNil or res.outputSize <= 0:
    return makeError(HAILO_INVALID_ARGUMENT, "output buffer is nil or empty").err

  let nmsShape = ad.detector.outputInfo.anon0.nms_shape
  let numClasses = int(nmsShape.number_of_classes)
  let maxBoxes = int(nmsShape.max_bboxes_per_class)

  let parseStart = getMonoTime()
  let raw = cast[ptr UncheckedArray[byte]](res.outputPtr)
  parseNmsByClassVariableInto(
    raw.toOpenArray(0, res.outputSize - 1),
    numClasses,
    maxBoxes,
    detections,
    appScoreThreshold
  )
  let parseUs = elapsedUs(parseStart)

  let sortStart = getMonoTime()
  detection.sortByScoreDesc(detections)
  let sortUs = elapsedUs(sortStart)

  result = (parseUs: parseUs, sortUs: sortUs).ok

# ------------------------------------------------------------------------------
#
# openAsyncDetector:
#
# ------------------------------------------------------------------------------

proc openAsyncDetector*(
  d: Detector;
  slotCount = 2
): HE[AsyncDetector] =
  ## Create an AsyncDetector from an already-opened Detector.
  ##
  ## submit() writes input synchronously on the caller thread.
  ## waitDetections() waits for the read thread result and parses NMS output.
  let validRes = validateDetector(d)
  if validRes.isErr:
    return validRes.error.err

  let runnerRes = d.openAsyncVStreamRunner(slotCount)
  if runnerRes.isErr:
    return runnerRes.error.err

  result = AsyncDetector(
    detector: d,
    runner: runnerRes.get
  ).ok

# ------------------------------------------------------------------------------
#
# close:
#
# ------------------------------------------------------------------------------

proc close*(ad: AsyncDetector): HE[void] =
  if ad.isNil:
    return okVoid()

  if not ad.runner.isNil:
    let res = ad.runner.close()
    ad.runner = nil
    ad.detector = nil
    return res

  ad.detector = nil
  result = okVoid()

# ------------------------------------------------------------------------------
#
# slotCount:
#
# ------------------------------------------------------------------------------

proc slotCount*(ad: AsyncDetector): int =
  if ad.isNil or ad.runner.isNil:
    return 0

  result = ad.runner.slotCount()

# ------------------------------------------------------------------------------
#
# inputSize:
#
# ------------------------------------------------------------------------------

proc inputSize*(ad: AsyncDetector): int =
  if ad.isNil or ad.runner.isNil:
    return 0

  result = ad.runner.inputSize()

# ------------------------------------------------------------------------------
#
# outputSize:
#
# ------------------------------------------------------------------------------

proc outputSize*(ad: AsyncDetector): int =
  if ad.isNil or ad.runner.isNil:
    return 0

  result = ad.runner.outputSize()

# ------------------------------------------------------------------------------
#
# availableSlots:
#
# ------------------------------------------------------------------------------

proc availableSlots*(ad: AsyncDetector): int =
  if ad.isNil or ad.runner.isNil:
    return 0

  result = ad.runner.availableSlots()

# ------------------------------------------------------------------------------
#
# submit:
#
# ------------------------------------------------------------------------------

proc submit*(
  ad: AsyncDetector;
  input: openArray[byte]
): HE[int] =
  ## Submit one input frame.
  ##
  ## Input is not copied.  The underlying vstream write is synchronous, so after
  ## submit() returns the caller may reuse the input buffer.
  if ad.isNil or ad.runner.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "async detector is nil").err

  result = ad.runner.submit(input)

# ------------------------------------------------------------------------------
#
# waitDetections:
#
# ------------------------------------------------------------------------------

proc waitDetections*(
  ad: AsyncDetector;
  detections: var seq[Detection];
  appScoreThreshold = 0.25'f32
): HE[AsyncDetectionResult] =
  ## Wait for one completed inference and parse NMS output into detections.
  ##
  ## The output slot is released before this function returns.  This means callers
  ## do not need to manage slot lifetime when they only need parsed detections.
  if ad.isNil or ad.runner.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "async detector is nil").err

  let waitRes = ad.runner.waitResult()
  if waitRes.isErr:
    return waitRes.error.err

  let vres = waitRes.get
  let parseRes = ad.parseOutputInto(vres, detections, appScoreThreshold)

  let releaseRes = ad.runner.releaseResult(vres)
  if releaseRes.isErr:
    return releaseRes.error.err

  if parseRes.isErr:
    return parseRes.error.err

  let timing = parseRes.get

  result = AsyncDetectionResult(
    slotIndex: vres.slotIndex,
    writeUs: vres.writeUs,
    readUs: vres.readUs,
    parseUs: timing.parseUs,
    sortUs: timing.sortUs,
    detectionCount: detections.len
  ).ok

# ------------------------------------------------------------------------------
#
# detectOnce:
#
# ------------------------------------------------------------------------------

proc detectOnce*(
  ad: AsyncDetector;
  input: openArray[byte];
  detections: var seq[Detection];
  appScoreThreshold = 0.25'f32
): HE[AsyncDetectionResult] =
  ## Convenience helper for one submit + waitDetections cycle.
  ##
  ## This is mostly useful for tests.  Pipelined callers should use submit() and
  ## waitDetections() separately.
  let submitRes = ad.submit(input)
  if submitRes.isErr:
    return submitRes.error.err

  result = ad.waitDetections(detections, appScoreThreshold)
