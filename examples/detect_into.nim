# ================================================================================
# detect_into.nim
#
# Smoke test for detectNmsByClass*Into() APIs.
#
# Usage:
#   nim c -r examples/detect_into.nim <hef> <input.raw> [loops] [warmup] [app_threshold] [hailo_threshold] [compare_wrapper]
#
# Example:
#   nim c -r examples/detect_into.nim yolov11n.hef dog.raw 20 5
#   nim c -r examples/detect_into.nim yolov11n.hef dog.raw 20 5 0.25 0.20 true
# ================================================================================

import std/[os, strformat, strutils, monotimes, times]

import hailort_nim
import hailort_nim/highlevel/detector
import hailort_nim/models/detection

# --------------------------------------------------------------------------------
# Helpers:
# --------------------------------------------------------------------------------
proc fail(msg: string) =
  stderr.writeLine(msg)
  quit(QuitFailure)

proc checkOrFail*[T](r: Result[T, HailoError]; context: string): T =
  if r.isErr:
    fail(&"{context}: {r.error}")
  result = r.value

proc checkOrFail*(r: Result[void, HailoError]; context: string) =
  if r.isErr:
    fail(&"{context}: {r.error}")

proc readFileBytes(path: string): seq[byte] =
  let s = readFile(path)
  result = newSeq[byte](s.len)
  if s.len > 0:
    copyMem(addr result[0], unsafeAddr s[0], s.len)

proc elapsedMs(started: MonoTime): float =
  let diff = getMonoTime() - started
  result = diff.inMicroseconds.float / 1000.0

proc bufferAddress(data: var openArray[byte]): string =
  if data.len == 0:
    return "nil"
  result = &"0x{cast[uint](addr data[0]):016X}"

proc firstDetectionAddress(detections: var seq[Detection]): string =
  if detections.len == 0:
    return "<empty>"
  result = &"0x{cast[uint](addr detections[0]):016X}"

proc parseBoolArg(s: string): bool =
  let lowered = s.toLowerAscii()
  result = lowered in ["1", "true", "yes", "on"]

proc printInputMetadata(det: Detector) =
  let md = checkOrFail(det.inputMetadata(), "Detector.inputMetadata")
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
  let md = checkOrFail(det.outputMetadata(), "Detector.outputMetadata")
  echo "Output metadata:"
  echo &"  name       : {md.name}"
  echo &"  network    : {md.networkName}"
  echo &"  type       : {md.dataType}"
  echo &"  order      : {md.pixelFormat}"
  echo &"  image_type : {md.imageType}"
  echo &"  flags      : {md.flags}"
  echo &"  shape      : {md.shape}"
  echo &"  frame_size : {det.outputSize()}"

proc printUsage() =
  echo "Usage: detect_into <hef> <input.raw> [loops] [warmup] [app_threshold] [hailo_threshold] [compare_wrapper]"
  echo ""
  echo "Examples:"
  echo "  detect_into yolov11n.hef dog_640x640x3.raw 20 5"
  echo "  detect_into yolov11n.hef dog_640x640x3.raw 20 5 0.25 0.20 true"

# --------------------------------------------------------------------------------
# Tests:
# --------------------------------------------------------------------------------
proc runDirectIntoSmokeTest(det: Detector; input: openArray[byte];
    outputBuf: var seq[byte]; detections: var seq[Detection];
    appScoreThreshold: float32) =
  echo ""
  echo "== direct detect Into API smoke test =="

  let inputImageType = checkOrFail(det.inputImageType(), "Detector.inputImageType")

  case inputImageType
  of itNhwc4:
    checkOrFail(
      det.detectNmsByClassNhwc4Into(
        input,
        outputBuf,
        detections,
        appScoreThreshold
      ),
      "Detector.detectNmsByClassNhwc4Into"
    )
    echo &"detectNmsByClassNhwc4Into : ok detections={detections.len}"
  else:
    checkOrFail(
      det.detectNmsByClassInto(
        input,
        outputBuf,
        detections,
        appScoreThreshold
      ),
      "Detector.detectNmsByClassInto"
    )
    echo &"detectNmsByClassInto      : ok detections={detections.len}"

proc runDetectAutoInto(det: Detector; input: openArray[byte];
    outputBuf: var seq[byte]; detections: var seq[Detection];
    loops: int; warmup: int; appScoreThreshold: float32) =
  echo ""
  echo "== detectNmsByClassAutoInto reuse test =="
  echo &"output buffer len  : {outputBuf.len}"
  echo &"output buffer addr : {bufferAddress(outputBuf)}"

  for i in 0 ..< warmup:
    let started = getMonoTime()
    checkOrFail(
      det.detectNmsByClassAutoInto(
        input,
        outputBuf,
        detections,
        appScoreThreshold
      ),
      "Detector.detectNmsByClassAutoInto warmup"
    )
    let ms = elapsedMs(started)
    echo &"Warmup[{i:>2}] : {ms:>8.3f} ms detections={detections.len} output_addr={bufferAddress(outputBuf)} first_detection={firstDetectionAddress(detections)}"

  var totalMs = 0.0
  var minMs = 1.0e18
  var maxMs = 0.0

  for i in 0 ..< loops:
    let outputBefore = bufferAddress(outputBuf)
    let detectionBefore = firstDetectionAddress(detections)

    let started = getMonoTime()
    checkOrFail(
      det.detectNmsByClassAutoInto(
        input,
        outputBuf,
        detections,
        appScoreThreshold
      ),
      "Detector.detectNmsByClassAutoInto"
    )
    let ms = elapsedMs(started)

    let outputAfter = bufferAddress(outputBuf)
    let detectionAfter = firstDetectionAddress(detections)

    if outputBefore != outputAfter:
      fail(&"output buffer address changed: before={outputBefore} after={outputAfter}")

    if detections.len > 0 and detectionBefore != "<empty>" and detectionBefore != detectionAfter:
      fail(&"detection buffer address changed: before={detectionBefore} after={detectionAfter}")

    if ms < minMs:
      minMs = ms
    if ms > maxMs:
      maxMs = ms
    totalMs += ms

    echo &"Loop[{i:>2}] : {ms:>8.3f} ms detections={detections.len} output={outputAfter} first_detection={detectionAfter}"

  let avgMs = totalMs / loops.float
  let fps = if avgMs > 0.0: 1000.0 / avgMs else: 0.0

  echo ""
  echo "Detect timing summary:"
  echo &"  total      : {totalMs:.3f} ms"
  echo &"  average    : {avgMs:.3f} ms"
  echo &"  min        : {minMs:.3f} ms"
  echo &"  max        : {maxMs:.3f} ms"
  echo &"  approx fps : {fps:.2f}"

proc runWrapperCompatibilityCheck(det: Detector; input: openArray[byte];
    outputBuf: var seq[byte]; detections: var seq[Detection];
    appScoreThreshold: float32) =
  echo ""
  echo "== wrapper compatibility check =="

  checkOrFail(
    det.detectNmsByClassAutoInto(
      input,
      outputBuf,
      detections,
      appScoreThreshold
    ),
    "Detector.detectNmsByClassAutoInto for wrapper check"
  )

  let wrapped = checkOrFail(
    det.detectNmsByClassAuto(input, appScoreThreshold),
    "Detector.detectNmsByClassAuto"
  )

  echo &"detectAutoInto detections : {detections.len}"
  echo &"detectAuto     detections : {wrapped.len}"

  if wrapped.len != detections.len:
    fail("detection count mismatch")

  for i in 0 ..< detections.len:
    if wrapped[i] != detections[i]:
      fail(&"detection mismatch at index {i}")

  echo "wrapper compatibility: ok"

# --------------------------------------------------------------------------------
# Main:
# --------------------------------------------------------------------------------
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
    let compareWrapper =
      if paramCount() >= 7: parseBoolArg(paramStr(7)) else: false

    let input = readFileBytes(rawPath)

    let openStarted = getMonoTime()
    var det = checkOrFail(
      Detector.open(hefPath, hailoNmsScoreThreshold = hailoNmsScoreThreshold),
      "Detector.open"
    )
    let openMs = elapsedMs(openStarted)
    defer:
      discard det.close()

    printInputMetadata(det)
    printOutputMetadata(det)
    echo &"Open time : {openMs:.3f} ms"
    echo &"Input len : {input.len}"
    echo &"Loops     : {loops}"
    echo &"Warmup    : {warmup}"
    echo &"App threshold   : {appScoreThreshold}"
    echo &"Hailo threshold : {hailoNmsScoreThreshold}"

    if input.len != det.inputSize():
      fail(&"input size mismatch: got {input.len}, expected {det.inputSize()}")

    var outputBuf = newSeq[byte](det.outputSize())
    var detections: seq[Detection] = @[]

    runDirectIntoSmokeTest(det, input, outputBuf, detections, appScoreThreshold)
    runDetectAutoInto(det, input, outputBuf, detections, loops, warmup, appScoreThreshold)

    if compareWrapper:
      runWrapperCompatibilityCheck(det, input, outputBuf, detections, appScoreThreshold)

  main()
