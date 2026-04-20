import std/[
  math, monotimes, os, sequtils, strformat, strutils, times
]
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

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc inputModeText(md: VStreamMetadata): string =
  case md.pixelFormat
  of pfNhwc:
    case md.shape.channels
    of 4:
      result = "NHWC4 (RGBX/RGBA-like raw buffer expected)"
    of 3:
      result = "NHWC3 (RGB raw buffer expected)"
    else:
      result = &"NHWC{md.shape.channels}"
  of pfNv12:
    result = "NV12"
  of pfNv21:
    result = "NV21"
  of pfYuy2:
    result = "YUY2"
  of pfI420:
    result = "I420"
  else:
    result = pixelFormatText(md.pixelFormat)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc durationMs(d: Duration): float =
  result = d.inNanoseconds.float / 1_000_000.0

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc runOne(det: Detector, input: openArray[byte], inputMd: VStreamMetadata,
    appScoreThreshold: float32): HE[seq[Detection]] =
  if inputMd.pixelFormat == pfNhwc and inputMd.shape.channels == 4:
    result = det.detectNmsByClassNhwc4(input,
      appScoreThreshold = appScoreThreshold)
  else:
    result = det.detectNmsByClass(input,
      appScoreThreshold = appScoreThreshold)


when isMainModule:
  proc main() =
    if paramCount() < 2:
      echo "Usage: infer_high_multi <model.hef> <input.raw> [loops] [warmup] [app_score_threshold] [hailo_nms_score_threshold]"
      echo ""
      echo "Examples:"
      echo "  infer_high_multi yolov11s.hef dog_640x640x3.raw"
      echo "  infer_high_multi yolov11s.hef dog_640x640x3.raw 50 5"
      echo "  infer_high_multi yolov11s_RGBX.hef frame_1920x1080x4.raw 50 5"
      quit(1)

    let hefPath = paramStr(1)
    let inputPath = paramStr(2)
    let loops =
      if paramCount() >= 3: parseInt(paramStr(3))
      else: 20
    let warmup =
      if paramCount() >= 4: parseInt(paramStr(4))
      else: 3
    let appScoreThreshold =
      if paramCount() >= 5: parseFloat(paramStr(5)).float32
      else: 0.25'f32
    let hailoNmsScoreThreshold =
      if paramCount() >= 6: parseFloat(paramStr(6)).float32
      else: 0.01'f32

    if loops <= 0:
      fail("loops must be > 0")
    if warmup < 0:
      fail("warmup must be >= 0")

    let openStart = getMonoTime()
    let det = getOrFail(
      Detector.open(
        hefPath,
        hailoNmsScoreThreshold = hailoNmsScoreThreshold,
        schedulingAlgorithm = HAILO_SCHEDULING_ALGORITHM_NONE
      ),
      "Detector.open"
    )
    let openMs = durationMs(getMonoTime() - openStart)
    defer:
      checkOrFail(det.close(), "Detector.close")

    printInputMetadata(det)
    printOutputMetadata(det)

    let input = loadRaw(inputPath)
    let inputMd = getOrFail(det.inputMetadata(), "Detector.inputMetadata")

    echo &"Input mode: {inputModeText(inputMd)}"
    echo &"Loops     : {loops}"
    echo &"Warmup    : {warmup}"
    echo &"Open time : {openMs:.3f} ms"

    if input.len != det.inputSize():
      fail(&"Input size mismatch: expected {det.inputSize()}, got {input.len}")

    var warmupDetections: seq[Detection] = @[]
    if warmup > 0:
      for i in 0 ..< warmup:
        let warmupStart = getMonoTime()
        warmupDetections = getOrFail(
          runOne(det, input, inputMd, appScoreThreshold),
          &"runOne(warmup #{i})"
        )
        let warmupMs = durationMs(getMonoTime() - warmupStart)
        echo &"Warmup[{i:>2}] : {warmupMs:>8.3f} ms  detections={warmupDetections.len}"

    var samplesMs = newSeq[float](loops)
    var lastDetections: seq[Detection] = @[]

    for i in 0 ..< loops:
      let loopStart = getMonoTime()
      lastDetections = getOrFail(
        runOne(det, input, inputMd, appScoreThreshold),
        &"runOne(loop #{i})"
      )
      let elapsedMs = durationMs(getMonoTime() - loopStart)
      samplesMs[i] = elapsedMs
      echo &"Loop[{i:>2}]   : {elapsedMs:>8.3f} ms  detections={lastDetections.len}"

    let totalMs = samplesMs.foldl(a + b, 0.0)
    let avgMs = totalMs / loops.float
    let minMs = min(samplesMs)
    let maxMs = max(samplesMs)
    let fps = if avgMs > 0: 1000.0 / avgMs else: 0.0

    echo ""
    echo "Timing summary:"
    echo &"  total        : {totalMs:.3f} ms"
    echo &"  average      : {avgMs:.3f} ms"
    echo &"  min          : {minMs:.3f} ms"
    echo &"  max          : {maxMs:.3f} ms"
    echo &"  approx fps   : {fps:.2f}"
    echo &"  last detect  : {lastDetections.len}"

    if lastDetections.len > 0:
      echo ""
      echo "Top detections (last loop):"
      for i, d in lastDetections[0 .. min(lastDetections.high, 9)]:
        echo &"[{i:>2}] class={d.classId:>2} label={labelFor(d.classId):<15} " &
            &"score={d.score:.4f} " &
            &"box=({d.yMin:.4f}, {d.xMin:.4f}, {d.yMax:.4f}, {d.xMax:.4f})"

  main()
