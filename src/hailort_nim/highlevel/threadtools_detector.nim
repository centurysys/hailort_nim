when not compileOption("threads"):
  {.error: "threadtools_detector requires --threads:on".}

import std/[monotimes, strformat, times]

import ./detector
import ./threadtools_vstream_runner
import ../lowlevel
import ../models/detection
import ../bindings/types
import ../internal/error

type
  ThreadtoolsDetectionResult* = object
    ## Result metadata for one completed threadtools-based detection.
    ##
    ## Detections themselves are written into the caller-provided seq.
    slotIndex*: int
    writeUs*: int64
    readUs*: int64
    parseUs*: int64
    sortUs*: int64
    detectionCount*: int

  ThreadtoolsDetector* = ref object
    ## Threadtools-based object detector built on top of
    ## ThreadtoolsVStreamRunner.
    ##
    ## This is YOLO/NMS-by-class specific.  The generic vstream overlap logic
    ## lives in ThreadtoolsVStreamRunner; this layer parses model output into a
    ## caller-owned seq[Detection] and always releases the output slot before
    ## returning.
    ##
    ## The source Detector must stay alive and activated until close() returns.
    detector: Detector
    runner: ThreadtoolsVStreamRunner

# ------------------------------------------------------------------------------
# Small helpers
# ------------------------------------------------------------------------------

proc elapsedUs(started: MonoTime): int64 {.inline.} =
  result = inMicroseconds(getMonoTime() - started)

# ------------------------------------------------------------------------------
# Validation
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
# Output parsing
# ------------------------------------------------------------------------------

proc parseOutputInto(
  td: ThreadtoolsDetector;
  res: ThreadtoolsVStreamResult;
  detections: var seq[Detection];
  appScoreThreshold: float32
): HE[tuple[parseUs, sortUs: int64]] =
  if td.isNil or td.detector.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "threadtools detector is nil").err

  if res.outputPtr.isNil or res.outputSize <= 0:
    return makeError(HAILO_INVALID_ARGUMENT, "output buffer is nil or empty").err

  let nmsShape = td.detector.outputInfo.anon0.nms_shape
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
# Construction / teardown
# ------------------------------------------------------------------------------

proc openThreadtoolsDetector*(
  d: Detector;
  config: ThreadtoolsVStreamRunnerConfig
): HE[ThreadtoolsDetector] =
  ## Create a ThreadtoolsDetector from an already-opened Detector.
  ##
  ## submit() writes input synchronously on the caller thread.
  ## waitDetections() waits for the read worker result and parses NMS output.
  let validRes = validateDetector(d)
  if validRes.isErr:
    return validRes.error.err

  let runnerRes = d.openThreadtoolsVStreamRunner(config)
  if runnerRes.isErr:
    return runnerRes.error.err

  result = ThreadtoolsDetector(
    detector: d,
    runner: runnerRes.get
  ).ok

proc openThreadtoolsDetector*(
  d: Detector;
  slotCount = 2
): HE[ThreadtoolsDetector] =
  var config = defaultThreadtoolsVStreamRunnerConfig()
  config.slotCount = slotCount
  config.inputQueueSize = slotCount
  config.resultQueueSize = slotCount

  result = d.openThreadtoolsDetector(config)

proc close*(td: ThreadtoolsDetector): HE[void] =
  if td.isNil:
    return okVoid()

  if not td.runner.isNil:
    let res = td.runner.close()
    td.runner = nil
    td.detector = nil
    return res

  td.detector = nil
  result = okVoid()

# ------------------------------------------------------------------------------
# Introspection
# ------------------------------------------------------------------------------

proc config*(td: ThreadtoolsDetector): ThreadtoolsVStreamRunnerConfig =
  if td.isNil or td.runner.isNil:
    return defaultThreadtoolsVStreamRunnerConfig()

  result = td.runner.config()

proc slotCount*(td: ThreadtoolsDetector): int =
  if td.isNil or td.runner.isNil:
    return 0

  result = td.runner.slotCount()

proc inputSize*(td: ThreadtoolsDetector): int =
  if td.isNil or td.runner.isNil:
    return 0

  result = td.runner.inputSize()

proc outputSize*(td: ThreadtoolsDetector): int =
  if td.isNil or td.runner.isNil:
    return 0

  result = td.runner.outputSize()

proc availableSlots*(td: ThreadtoolsDetector): int =
  if td.isNil or td.runner.isNil:
    return 0

  result = td.runner.availableSlots()

proc isRunning*(td: ThreadtoolsDetector): bool =
  if td.isNil or td.runner.isNil:
    return false

  result = td.runner.isRunning()

# ------------------------------------------------------------------------------
# Submit / receive
# ------------------------------------------------------------------------------

proc submit*(
  td: ThreadtoolsDetector;
  input: openArray[byte]
): HE[int] =
  ## Submit one input frame.
  ##
  ## Input is not copied.  The underlying vstream write is synchronous, so after
  ## submit() returns the caller may reuse the input buffer.
  if td.isNil or td.runner.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "threadtools detector is nil").err

  result = td.runner.submit(input)

proc waitDetections*(
  td: ThreadtoolsDetector;
  detections: var seq[Detection];
  appScoreThreshold = 0.25'f32
): HE[ThreadtoolsDetectionResult] =
  ## Wait for one completed inference and parse NMS output into detections.
  ##
  ## The output slot is released before this function returns.  This means
  ## callers do not need to manage slot lifetime when they only need parsed
  ## detections.
  if td.isNil or td.runner.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "threadtools detector is nil").err

  let waitRes = td.runner.waitResult()
  if waitRes.isErr:
    return waitRes.error.err

  let vres = waitRes.get
  let parseRes = td.parseOutputInto(vres, detections, appScoreThreshold)

  let releaseRes = td.runner.releaseResult(vres)
  if releaseRes.isErr:
    return releaseRes.error.err

  if parseRes.isErr:
    return parseRes.error.err

  let timing = parseRes.get

  result = ThreadtoolsDetectionResult(
    slotIndex: vres.slotIndex,
    writeUs: vres.writeUs,
    readUs: vres.readUs,
    parseUs: timing.parseUs,
    sortUs: timing.sortUs,
    detectionCount: detections.len
  ).ok

proc detectOnce*(
  td: ThreadtoolsDetector;
  input: openArray[byte];
  detections: var seq[Detection];
  appScoreThreshold = 0.25'f32
): HE[ThreadtoolsDetectionResult] =
  ## Convenience helper for one submit + waitDetections cycle.
  ##
  ## This is mostly useful for tests.  Pipelined callers should use submit() and
  ## waitDetections() separately.
  let submitRes = td.submit(input)
  if submitRes.isErr:
    return submitRes.error.err

  result = td.waitDetections(detections, appScoreThreshold)
