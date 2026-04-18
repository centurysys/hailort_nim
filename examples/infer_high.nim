import std/[os, strformat, strutils]
import ../src/hailort_nim
import ./common/[common, labels]

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc labelFor(classId: int): string =
  if classId >= 0 and classId < cocoLabels.len:
    cocoLabels[classId]
  else:
    &"class_{classId}"


when isMainModule:
  proc main() =
    if paramCount() < 2:
      echo "Usage: infer_high_ex1 <model.hef> <input.bin> [app_score_threshold] [hailo_nms_score_threshold]"
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

    echo &"Input frame size:  {det.inputSize()}"
    echo &"Output frame size: {det.outputSize()}"

    let input = loadRaw(inputPath)
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
