import std/[os, strutils, strformat, monotimes, times]
import hailort_nim
import ./common/[common, labels]

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc readFileBytes(path: string): seq[byte] =
  let s = readFile(path)
  result = newSeq[byte](s.len)
  if s.len > 0:
    copyMem(addr result[0], unsafeAddr s[0], s.len)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc printInputMetadata(det: Detector) =
  let md = getOrFail(det.inputMetadata(), "Detector.inputMetadata")
  echo "Input metadata:"
  echo &"  name        : {md.name}"
  echo &"  network     : {md.networkName}"
  echo &"  type        : {md.dataType}"
  echo &"  order       : {md.pixelFormat}"
  echo &"  image_type  : {md.imageType}"
  echo &"  flags       : {md.flags}"
  echo &"  shape       : {md.shape}"
  echo &"  frame_size  : {det.inputSize()}"

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc printOutputMetadata(det: Detector) =
  let md = getOrFail(det.outputMetadata(), "Detector.outputMetadata")
  echo "Output metadata:"
  echo &"  name        : {md.name}"
  echo &"  network     : {md.networkName}"
  echo &"  type        : {md.dataType}"
  echo &"  order       : {md.pixelFormat}"
  echo &"  image_type  : {md.imageType}"
  echo &"  flags       : {md.flags}"
  echo &"  shape       : {md.shape}"
  echo &"  frame_size  : {det.outputSize()}"

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc printInputMode(det: Detector) =
  let it = getOrFail(det.inputImageType(), "Detector.inputMode")
  case it
  of itNhwc3:
    echo "Input mode: NHWC3 (RGB raw buffer expected)"
  of itNhwc4:
    echo "Input mode: NHWC4 (RGBX/RGBA-like raw buffer expected)"
  of itNv12:
    echo "Input mode: NV12"
  of itNv21:
    echo "Input mode: NV21"
  of itYuy2:
    echo "Input mode: YUY2"
  of itI420:
    echo "Input mode: I420"
  else:
    echo "Input mode: UNKNOWN"

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc printUsage() =
  echo "Usage: infer_high_multi <model.hef> <input.raw> [loops] [warmup] [app_score_threshold] [hailo_nms_score_threshold]"
  echo ""
  echo "Examples:"
  echo "  infer_high_multi yolov11s.hef dog_640x640x3.raw 20 5"
  echo "  infer_high_multi yolov11s_RGBX.hef frame_1920x1080x4.raw 20 5"

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
when isMainModule:
  proc main() =
    if paramCount() < 2:
      printUsage()
      quit(QuitFailure)

    let hefPath = paramStr(1)
    let rawPath = paramStr(2)

    let loops =
      if paramCount() >= 3:
        parseInt(paramStr(3))
      else:
        20

    let warmup =
      if paramCount() >= 4:
        parseInt(paramStr(4))
      else:
        5

    let appScoreThreshold =
      if paramCount() >= 5:
        parseFloat(paramStr(5)).float32
      else:
        0.25'f32

    let hailoNmsScoreThreshold =
      if paramCount() >= 6:
        parseFloat(paramStr(6)).float32
      else:
        0.20'f32

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
    printInputMode(det)
    echo &"Loops     : {loops}"
    echo &"Warmup    : {warmup}"
    echo &"Open time : {openElapsed.inMicroseconds.float / 1000.0:.3f} ms"

    var lastDetections: seq[Detection] = @[]

    for i in 0 ..< warmup:
      let t0 = getMonoTime()
      let detections = getOrFail(
        det.detectNmsByClassAuto(input),
        "Detector.detectNmsByClassAuto"
      )
      let elapsed = getMonoTime() - t0
      echo &"Warmup[{i:>2}] : {elapsed.inMicroseconds.float / 1000.0:>8.3f} ms  detections={detections.len}"
      lastDetections = detections

    var totalMs = 0.0
    var minMs = 1.0e18
    var maxMs = 0.0

    for i in 0 ..< loops:
      let t0 = getMonoTime()
      let detections = getOrFail(
        det.detectNmsByClassAuto(input),
        "Detector.detectNmsByClassAuto"
      )
      let elapsed = getMonoTime() - t0
      let ms = elapsed.inMicroseconds.float / 1000.0

      if ms < minMs:
        minMs = ms
      if ms > maxMs:
        maxMs = ms
      totalMs += ms

      echo &"Loop[{i:>2}]   : {ms:>8.3f} ms  detections={detections.len}"
      lastDetections = detections

    let avgMs = totalMs / loops.float
    let fps =
      if avgMs > 0.0:
        1000.0 / avgMs
      else:
        0.0

    echo ""
    echo "Timing summary:"
    echo &"  total        : {totalMs:.3f} ms"
    echo &"  average      : {avgMs:.3f} ms"
    echo &"  min          : {minMs:.3f} ms"
    echo &"  max          : {maxMs:.3f} ms"
    echo &"  approx fps   : {fps:.2f}"
    echo &"  last detect  : {lastDetections.len}"

    let filtered = lastDetections.filterByScore(appScoreThreshold)
    let labels = cocoLabels

    echo ""
    echo "Top detections (last loop):"
    for i, d in filtered:
      if i >= 10:
        break

      let label =
        if d.classId >= 0 and d.classId < labels.len:
          labels[d.classId]
        else:
          "class_" & $d.classId

      echo &"[{i:>2}] class={d.classId:>2} label={label:<15} score={d.score:.4f} " &
          &"box=({d.xMin:.4f}, {d.yMin:.4f}, {d.xMax:.4f}, {d.yMax:.4f})"

  main()
