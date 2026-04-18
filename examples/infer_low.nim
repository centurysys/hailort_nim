import std/[
  algorithm,
  os,
  sequtils,
  strformat,
  strutils,
]
import ../src/hailort_nim/lowlevel
import ./common/[common, labels]

type
  Detection* = object
    classId*: int
    score*: float32
    yMin*: float32
    xMin*: float32
    yMax*: float32
    xMax*: float32

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc readF32Le(data: openArray[byte], offset: int): float32 =
  if offset + 4 > data.len:
    fail("readF32Le: offset out of range")
  copyMem(addr result, unsafeAddr data[offset], 4)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc loadRawRgb(path: string, expectedSize: int): seq[byte] =
  let s = readFile(path)
  if s.len != expectedSize:
    fail(&"Raw RGB payload size mismatch: expected {expectedSize}," &
        &" got {s.len}")
  result = newSeq[byte](expectedSize)
  if expectedSize > 0:
    copyMem(addr result[0], unsafeAddr s[0], expectedSize)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc labelFor*(classId: int): string =
  result =
    if classId >= 0 and classId < cocoLabels.len:
      cocoLabels[classId]
    else:
      &"class_{classId}"

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc parseNmsByClassVariable*(raw: openArray[byte], numberOfClasses,
    maxBboxesPerClass: int): seq[Detection] =
  ## Parse HAILO_FORMAT_ORDER_HAILO_NMS_BY_CLASS output.
  ##
  ## Important:
  ## - The output buffer size is the maximum frame size.
  ## - The on-wire layout is variable-length per class:
  ##     float32 bbox_count,
  ##     hailo_bbox_float32_t bbox[bbox_count],
  ## - Therefore, the parser must advance by 4 + bbox_count * 20 bytes per class,
  ##   NOT by 4 + maxBboxesPerClass * 20 bytes.
  var offset = 0
  let rawLen = raw.len

  for classId in 0 ..< numberOfClasses:
    if offset + 4 > rawLen:
      fail(&"NMS parse failed: truncated before class count of class {classId}")
    let countF = readF32Le(raw, offset)
    offset += 4
    var count = int(countF)
    if count < 0:
      count = 0
    if count > maxBboxesPerClass:
      # Guard against corrupted data
      count = maxBboxesPerClass
    for _ in 0 ..< count:
      if offset + 20 > rawLen:
        fail(&"NMS parse failed: truncated inside detections of class {classId}")
      let yMin = readF32Le(raw, offset + 0)
      let xMin = readF32Le(raw, offset + 4)
      let yMax = readF32Le(raw, offset + 8)
      let xMax = readF32Le(raw, offset + 12)
      let score = readF32Le(raw, offset + 16)
      offset += 20
      let det = Detection(classId: classId, score: score,
          yMin: yMin, xMin: xMin, yMax: yMax, xMax: xMax)
      result.add(det)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc dumpCountSummary(raw: openArray[byte], numberOfClasses, maxBboxesPerClass: int) =
  var
    offset = 0
    nonZero = 0
  for classId in 0 ..< numberOfClasses:
    if offset + 4 > raw.len:
      break
    let countF = readF32Le(raw, offset)
    offset += 4
    var count = int(countF)
    if count < 0: count = 0
    if count > maxBboxesPerClass: count = maxBboxesPerClass
    if count > 0:
      inc nonZero
      echo &"  class[{classId}] {labelFor(classId)}, count={count}"
    let bytesForBoxes = count * 20
    if offset + bytesForBoxes > raw.len:
      break
    offset += bytesForBoxes
  echo &"Non-zero classes: {nonZero}"


when isMainModule:
  proc main() =
    if paramCount() < 2:
      echo "Usage: infer_raw_fixed <model.hef> <input.bin> [app_score_threshold] [hailo_nms_score_threshold]"
      echo "  input.bin must be raw RGB bytes only (no PPM header), sized exactly 640*640*3 for this HEF"
      quit 1

    let hefPath = paramStr(1)
    let rawPath = paramStr(2)
    let appScoreThreshold =
      if paramCount() >= 3: parseFloat(paramStr(3)).float32
      else: 0.25'f32
    let hailoNmsScoreThreshold =
      if paramCount() >= 4: parseFloat(paramStr(4)).float32
      else: 0.01'f32

    echo "Opening HEF: ", hefPath
    let hefObj = getOrFail(openHef(hefPath), "openHef")
    defer: discard hefObj.close()
    echo "HEF opened"

    var vdevParams = getOrFail(initVdeviceParams(), "initVdeviceParams")
    vdevParams.scheduling_algorithm = HAILO_SCHEDULING_ALGORITHM_NONE

    let vdevObj = getOrFail(createVdevice(vdevParams), "createVdevice(params)")
    defer: discard vdevObj.close()
    echo "VDevice created"

    let ngObj = getOrFail(configureOne(vdevObj, hefObj), "configureOne")
    defer: discard ngObj.close()
    echo "Network group configured"

    let inputParams = getOrFail(makeInputVstreamParams(ngObj), "makeInputVstreamParams")
    let outputParams = getOrFail(makeOutputVstreamParams(ngObj), "makeOutputVstreamParams")
    if inputParams.len != 1:
      fail("Expected exactly 1 input vstream, got " & $inputParams.len)
    if outputParams.len != 1:
      fail("Expected exactly 1 output vstream, got " & $outputParams.len)

    let inputVstreams = getOrFail(createInputVstreams(ngObj, inputParams), "createInputVstreams")
    defer: discard inputVstreams.close()
    let outputVstreams = getOrFail(createOutputVstreams(ngObj, outputParams), "createOutputVstreams")
    defer: discard outputVstreams.close()

    let inputStream = inputVstreams[0]
    let outputStream = outputVstreams[0]

    let inFrameSize = getOrFail(inputStream.frameSize(), "input frame size")
    let outFrameSize = getOrFail(outputStream.frameSize(), "output frame size")
    let outInfo = getOrFail(outputStream.info(), "output info")

    echo "Input vstream:  ", inputStream.name().getOrFail("input name")
    echo "Output vstream: ", outputStream.name().getOrFail("output name")
    echo "Input frame size:  ", inFrameSize
    echo "Output frame size: ", outFrameSize

    if outInfo.format.order != HAILO_FORMAT_ORDER_HAILO_NMS_BY_CLASS:
      fail("This app currently expects HAILO_FORMAT_ORDER_HAILO_NMS_BY_CLASS output, got order=" & $ord(outInfo.format.order))

    let nmsShape = outInfo.anon0.nms_shape
    let numClasses = int(nmsShape.number_of_classes)
    let maxBoxes = int(nmsShape.max_bboxes_per_class)
    echo "NMS classes: ", numClasses
    echo "NMS max boxes/class: ", maxBoxes
    echo "Application score threshold: ", appScoreThreshold
    echo "Hailo NMS score threshold: ", hailoNmsScoreThreshold

    let rgb = loadRawRgb(rawPath, inFrameSize)
    echo "Loaded raw RGB: ", rawPath, " (", rgb.len, " bytes)"

    discard outputStream.setNmsScoreThreshold(hailoNmsScoreThreshold)
    echo "Configured output vstream NMS score threshold"

    let activated = getOrFail(ngObj.activate(), "activate")
    defer: discard activated.close()
    echo "Network group activated"

    checkOrFail(inputStream.write(rgb), "input write")
    echo "Input frame written"

    let rawOutput = getOrFail(outputStream.read(outFrameSize), "output read")
    echo "Output frame read"

    echo "Count summary:"
    dumpCountSummary(rawOutput, numClasses, maxBoxes)

    var detections = parseNmsByClassVariable(rawOutput, numClasses, maxBoxes)
    detections.sort(proc(a, b: Detection): int = cmp(b.score, a.score))

    echo "Top raw detections before app thresholding:"
    if detections.len == 0:
      echo "  (none)"
    else:
      for i in 0..<min(detections.len, 10):
        let det = detections[i]
        echo "  [", i, "] ", labelFor(det.classId),
          " score=", formatFloat(det.score, ffDecimal, 6),
          " box=(ymin=", formatFloat(det.yMin, ffDecimal, 4),
          ", xmin=", formatFloat(det.xMin, ffDecimal, 4),
          ", ymax=", formatFloat(det.yMax, ffDecimal, 4),
          ", xmax=", formatFloat(det.xMax, ffDecimal, 4), ")"

    detections.keepItIf(it.score >= appScoreThreshold)
    if detections.len == 0:
      echo "No detections above application threshold ", appScoreThreshold
      quit 0

    echo "Top detections:"
    for i in 0..<min(detections.len, 10):
      let det = detections[i]
      echo "  [", i, "] ", labelFor(det.classId),
        " score=", formatFloat(det.score, ffDecimal, 4),
        " box=(ymin=", formatFloat(det.yMin, ffDecimal, 4),
        ", xmin=", formatFloat(det.xMin, ffDecimal, 4),
        ", ymax=", formatFloat(det.yMax, ffDecimal, 4),
        ", xmax=", formatFloat(det.xMax, ffDecimal, 4), ")"

    let best = detections[0]
    echo "Best match: ", labelFor(best.classId), " (score=", formatFloat(best.score, ffDecimal, 4), ")"

  main()
