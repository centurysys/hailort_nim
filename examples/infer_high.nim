import std/[os, strutils, strformat]
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
  let it = getOrFail(det.inputImageType(), "printInputMode")
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
  echo "Usage: infer_high <model.hef> <input.raw> [app_score_threshold] [hailo_nms_score_threshold]"
  echo ""
  echo "Examples:"
  echo "  infer_high yolov11s.hef dog_640x640x3.raw"
  echo "  infer_high yolov11s_RGBX.hef frame_1920x1080x4.raw"

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

    let appScoreThreshold =
      if paramCount() >= 3:
        parseFloat(paramStr(3)).float32
      else:
        0.25'f32

    let hailoNmsScoreThreshold =
      if paramCount() >= 4:
        parseFloat(paramStr(4)).float32
      else:
        0.20'f32

    let input = readFileBytes(rawPath)

    var det = getOrFail(
      Detector.open(hefPath, hailoNmsscoreThreshold = hailoNmsScoreThreshold),
      "Detector.open"
    )
    defer:
      discard det.close()

    printInputMetadata(det)
    printOutputMetadata(det)
    printInputMode(det)

    let detections = getOrFail(
      det.detectNmsByClassAuto(input),
      "Detector.detectNmsByClassAuto"
    )

    let filtered = detections.filterByScore(appScoreThreshold)
    echo &"Detection count: {filtered.len}"

    let labels = cocoLabels

    for i, d in filtered:
      let label =
        if d.classId >= 0 and d.classId < labels.len:
          labels[d.classId]
        else:
          "class_" & $d.classId

      echo &"[{i:>2}] class={d.classId:>2} label={label:<15} score={d.score:.4f} " &
          &"box=({d.xMin:.4f}, {d.yMin:.4f}, {d.xMax:.4f}, {d.yMax:.4f})"

  main()
