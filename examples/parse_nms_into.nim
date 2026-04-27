import std/[os, strutils, strformat, monotimes, times]

import hailort_nim
import hailort_nim/highlevel/detector
import hailort_nim/models/detection
import ./common/common

# ------------------------------------------------------------------------------
# File helpers:
# ------------------------------------------------------------------------------
proc readFileBytes(path: string): seq[byte] =
  let s = readFile(path)
  result = newSeq[byte](s.len)
  if s.len > 0:
    copyMem(addr result[0], unsafeAddr s[0], s.len)

# ------------------------------------------------------------------------------
# Debug helpers:
# ------------------------------------------------------------------------------
proc bufferAddress(data: var openArray[byte]): string =
  if data.len == 0:
    return "nil"
  result = "0x" & cast[uint](addr data[0]).toHex()

proc firstDetectionAddress(detections: var seq[Detection]): string =
  if detections.len == 0:
    return "<empty>"
  result = "0x" & cast[uint](addr detections[0]).toHex()

proc printInputMetadata(det: Detector) =
  let md = getOrFail(det.inputMetadata(), "Detector.inputMetadata")
  echo "Input metadata:"
  echo &"  name       : {md.name}"
  echo &"  network    : {md.networkName}"
  echo &"  type       : {md.dataType}"
  echo &"  order      : {md.pixelFormat}"
  echo &"  image_type : {md.imageType}"
  echo &"  flags      : {md.flags}"
  echo &"  shape      : {md.shape}"
  echo &"  frame_size : {det.inputSize()}"

proc printOutputMetadata(det: Detector) =
  let md = getOrFail(det.outputMetadata(), "Detector.outputMetadata")
  echo "Output metadata:"
  echo &"  name       : {md.name}"
  echo &"  network    : {md.networkName}"
  echo &"  type       : {md.dataType}"
  echo &"  order      : {md.pixelFormat}"
  echo &"  image_type : {md.imageType}"
  echo &"  flags      : {md.flags}"
  echo &"  shape      : {md.shape}"
  echo &"  frame_size : {det.outputSize()}"

proc getNmsShape(det: Detector; numberOfClasses: var int; maxBboxesPerClass: var int) =
  ## Use the Hailo NMS metadata stored in VstreamInfo.
  ## For YOLO NMS output this is more explicit than deriving values from
  ## the generic image shape fields.
  let nmsShape = det.outputInfo.anon0.nms_shape
  numberOfClasses = int(nmsShape.number_of_classes)
  maxBboxesPerClass = int(nmsShape.max_bboxes_per_class)

proc printUsage() =
  echo "Usage: parse_nms_into <hef> <raw_input> [loops] [warmup] [app_score_threshold] [hailo_nms_score_threshold] [check_wrapper]"
  echo ""
  echo "Examples:"
  echo "  parse_nms_into yolov11n.hef dog_640x640x3.raw 20 5"
  echo "  parse_nms_into yolov11n.hef dog_640x640x3.raw 20 5 0.25 0.20 true"

# ------------------------------------------------------------------------------
# Tests:
# ------------------------------------------------------------------------------
proc runParseInto(det: Detector; output: var seq[byte]; detections: var seq[Detection];
    numberOfClasses: int; maxBboxesPerClass: int; appScoreThreshold: float32;
    loops: int) =
  echo ""
  echo "== parseNmsByClassVariableInto reuse test =="

  var totalMs = 0.0
  var minMs = 1.0e18
  var maxMs = 0.0

  for i in 0 ..< loops:
    let beforeAddr = firstDetectionAddress(detections)

    let t0 = getMonoTime()
    parseNmsByClassVariableInto(
      output,
      numberOfClasses,
      maxBboxesPerClass,
      detections,
      appScoreThreshold
    )
    let elapsed = getMonoTime() - t0

    let afterAddr = firstDetectionAddress(detections)
    let ms = elapsed.inMicroseconds.float / 1000.0
    if ms < minMs:
      minMs = ms
    if ms > maxMs:
      maxMs = ms
    totalMs += ms

    echo &"Loop[{i:>2}] : {ms:>8.3f} ms detections={detections.len} before={beforeAddr} after={afterAddr}"

  let avgMs = totalMs / loops.float
  echo ""
  echo "Parse timing summary:"
  echo &"  total   : {totalMs:.3f} ms"
  echo &"  average : {avgMs:.3f} ms"
  echo &"  min     : {minMs:.3f} ms"
  echo &"  max     : {maxMs:.3f} ms"

proc runWrapperCompatibilityCheck(output: openArray[byte]; detections: seq[Detection];
    numberOfClasses: int; maxBboxesPerClass: int; appScoreThreshold: float32) =
  echo ""
  echo "== wrapper compatibility check =="

  let wrapped = parseNmsByClassVariable(
    output,
    numberOfClasses,
    maxBboxesPerClass,
    appScoreThreshold
  )

  echo &"parseInto detections : {detections.len}"
  echo &"wrapper detections   : {wrapped.len}"

  if wrapped.len != detections.len:
    echo "ERROR: detection count mismatch"
    quit(QuitFailure)

  for i in 0 ..< detections.len:
    if wrapped[i] != detections[i]:
      echo &"ERROR: detection mismatch at index {i}"
      quit(QuitFailure)

  echo "wrapper compatibility: ok"

when isMainModule:
  proc main() =
    if paramCount() < 2:
      printUsage()
      quit(QuitFailure)

    let hefPath = paramStr(1)
    let rawPath = paramStr(2)
    let loops = if paramCount() >= 3: parseInt(paramStr(3)) else: 20
    let warmup = if paramCount() >= 4: parseInt(paramStr(4)) else: 5
    let appScoreThreshold =
      if paramCount() >= 5: parseFloat(paramStr(5)).float32 else: 0.25'f32
    let hailoNmsScoreThreshold =
      if paramCount() >= 6: parseFloat(paramStr(6)).float32 else: 0.20'f32
    let checkWrapper =
      if paramCount() >= 7: parseBool(paramStr(7)) else: false

    let input = readFileBytes(rawPath)

    let openStart = getMonoTime()
    var det = getOrFail(
      Detector.open(hefPath, hailoNmsScoreThreshold = hailoNmsScoreThreshold),
      "Detector.open"
    )
    let openElapsed = getMonoTime() - openStart
    defer:
      discard det.close()

    printInputMetadata(det)
    printOutputMetadata(det)
    echo &"Open time : {openElapsed.inMicroseconds.float / 1000.0:.3f} ms"
    echo &"Input len : {input.len}"
    echo &"Loops     : {loops}"
    echo &"Warmup    : {warmup}"
    echo &"Threshold : {appScoreThreshold}"

    if input.len != det.inputSize():
      echo &"ERROR: input size mismatch: got {input.len}, expected {det.inputSize()}"
      quit(QuitFailure)

    var numberOfClasses = 0
    var maxBboxesPerClass = 0
    getNmsShape(det, numberOfClasses, maxBboxesPerClass)
    if numberOfClasses <= 0 or maxBboxesPerClass <= 0:
      echo &"ERROR: invalid NMS shape: classes={numberOfClasses}, max_boxes={maxBboxesPerClass}"
      quit(QuitFailure)

    echo &"NMS classes : {numberOfClasses}"
    echo &"NMS max box : {maxBboxesPerClass}"

    var output = newSeq[byte](det.outputSize())
    var detections: seq[Detection] = @[]

    echo ""
    echo "== inferInto warmup =="
    for i in 0 ..< warmup:
      let t0 = getMonoTime()
      checkOrFail(det.inferInto(input, output), "Detector.inferInto warmup")
      parseNmsByClassVariableInto(
        output,
        numberOfClasses,
        maxBboxesPerClass,
        detections,
        appScoreThreshold
      )
      let elapsed = getMonoTime() - t0
      echo &"Warmup[{i:>2}] : {elapsed.inMicroseconds.float / 1000.0:>8.3f} ms detections={detections.len} output_addr={bufferAddress(output)} first_detection={firstDetectionAddress(detections)}"

    checkOrFail(det.inferInto(input, output), "Detector.inferInto before parse test")
    runParseInto(
      det,
      output,
      detections,
      numberOfClasses,
      maxBboxesPerClass,
      appScoreThreshold,
      loops
    )

    if checkWrapper:
      runWrapperCompatibilityCheck(
        output,
        detections,
        numberOfClasses,
        maxBboxesPerClass,
        appScoreThreshold
      )

  main()
