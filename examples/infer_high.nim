import std/[os, strformat, strutils]
import ../src/hailort_nim
import ./common/[common, labels]

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc labelFor(classId: int): string =
  if classId >= 0 and classId < cocoLabels.len:
    result = cocoLabels[classId]
  else:
    result = &"class_{classId}"

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc formatFlagsText(flags: set[FormatFlag]): string =
  if flags.len == 0:
    return "NONE"

  var parts: seq[string] = @[]
  for flag in flags:
    parts.add($flag)
  result = parts.join("|")

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc pixelFormatText(fmt: PixelFormat): string =
  result = $fmt
  if result.startsWith("pf"):
    result = result[2 .. ^1]
  result = result.toUpperAscii()

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc dataTypeText(dt: TensorDataType): string =
  result = case dt
    of tdtAuto:
      "AUTO"
    of tdtUint8:
      "UINT8"
    of tdtUint16:
      "UINT16"
    of tdtFloat32:
      "FLOAT32"
    else:
      "UNKNOWN"

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc shapeText(shape: ImageShape): string =
  result = &"{shape.height} x {shape.width} x {shape.channels}"

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc printInputMetadata(det: Detector) =
  let md = getOrFail(det.inputMetadata(), "Detector.inputMetadata")
  echo "Input metadata:"
  echo &"  name        : {md.name}"
  echo &"  network     : {md.networkName}"
  echo &"  type        : {dataTypeText(md.dataType)}"
  echo &"  order       : {pixelFormatText(md.pixelFormat)}"
  echo &"  flags       : {formatFlagsText(md.flags)}"
  echo &"  shape       : {shapeText(md.shape)}"
  echo &"  frame_size  : {det.inputSize()}"

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc printOutputMetadata(det: Detector) =
  let md = getOrFail(det.outputMetadata(), "Detector.outputMetadata")
  echo "Output metadata:"
  echo &"  name        : {md.name}"
  echo &"  network     : {md.networkName}"
  echo &"  type        : {dataTypeText(md.dataType)}"
  echo &"  order       : {pixelFormatText(md.pixelFormat)}"
  echo &"  flags       : {formatFlagsText(md.flags)}"
  echo &"  shape       : {shapeText(md.shape)}"
  echo &"  frame_size  : {det.outputSize()}"


when isMainModule:
  proc main() =
    if paramCount() < 2:
      echo "Usage: infer_high <model.hef> <input.raw> [app_score_threshold] [hailo_nms_score_threshold]"
      echo ""
      echo "Examples:"
      echo "  infer_high yolov11s.hef dog_640x640x3.raw"
      echo "  infer_high yolov11s_RGBX.hef frame_1920x1080x4.raw"
      quit(1)

    let hefPath = paramStr(1)
    let inputPath = paramStr(2)
    let appScoreThreshold =
      if paramCount() >= 3: parseFloat(paramStr(3)).float32
      else: 0.25'f32
    let hailoNmsScoreThreshold =
      if paramCount() >= 4: parseFloat(paramStr(4)).float32
      else: 0.01'f32

    let det = getOrFail(
      Detector.open(
        hefPath,
        hailoNmsScoreThreshold = hailoNmsScoreThreshold,
        schedulingAlgorithm = HAILO_SCHEDULING_ALGORITHM_NONE
      ),
      "Detector.open"
    )
    defer:
      checkOrFail(det.close(), "Detector.close")

    printInputMetadata(det)
    printOutputMetadata(det)

    let input = loadRaw(inputPath)

    let inputMd = getOrFail(det.inputMetadata(), "Detector.inputMetadata")
    case inputMd.pixelFormat
    of pfNhwc:
      case inputMd.shape.channels
      of 4:
        echo "Input mode: NHWC4 (RGBX/RGBA-like raw buffer expected)"
      of 3:
        echo "Input mode: NHWC3 (RGB raw buffer expected)"
      else:
        echo &"Input mode: NHWC{inputMd.shape.channels}"
    of pfNv12:
      echo "Input mode: NV12"
    of pfNv21:
      echo "Input mode: NV21"
    of pfYuy2:
      echo "Input mode: YUY2"
    of pfI420:
      echo "Input mode: I420"
    else:
      echo &"Input mode: {pixelFormatText(inputMd.pixelFormat)}"

    if input.len != det.inputSize():
      fail(&"Input size mismatch: expected {det.inputSize()}, got {input.len}")

    let detections = getOrFail(
      det.detectNmsByClass(input, appScoreThreshold = appScoreThreshold),
      "Detector.detectNmsByClass"
    )

    echo &"Detection count: {detections.len}"
    for i, d in detections:
      echo &"[{i:>2}] class={d.classId:>2} label={labelFor(d.classId):<15} " &
          &"score={d.score:.4f} " &
          &"box=({d.yMin:.4f}, {d.xMin:.4f}, {d.yMax:.4f}, {d.xMax:.4f})"

  main()
