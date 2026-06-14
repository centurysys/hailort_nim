import std/[os, strformat, strutils]

import hailort_nim

const
  ModelWidth = 640
  ModelHeight = 640

proc usage() =
  echo "Usage: multi_output_yolov8_pose_probe <model.hef> <input_640x640_rgb.raw> [scoreThreshold] [candidateLimit] [overlay.ppm] [jointThreshold] [iouThreshold] [maxPoses]"
  echo "Example:"
  echo "  ./multi_output_yolov8_pose_probe yolov8s_pose.hef pose_test_640x640_rgb.raw 0.25 100 pose_overlay.ppm 0.5 0.45 20"

proc clampInt(v, lo, hi: int): int {.inline.} =
  if v < lo:
    lo
  elif v > hi:
    hi
  else:
    v

proc drawPixel(rgb: var seq[byte]; x, y: int; r, g, b: byte) =
  if x < 0 or x >= ModelWidth or y < 0 or y >= ModelHeight:
    return
  let idx = (y * ModelWidth + x) * 3
  rgb[idx + 0] = r
  rgb[idx + 1] = g
  rgb[idx + 2] = b

proc drawRect(rgb: var seq[byte]; x1, y1, x2, y2: int; r, g, b: byte) =
  let ax = clampInt(min(x1, x2), 0, ModelWidth - 1)
  let bx = clampInt(max(x1, x2), 0, ModelWidth - 1)
  let ay = clampInt(min(y1, y2), 0, ModelHeight - 1)
  let by = clampInt(max(y1, y2), 0, ModelHeight - 1)
  for x in ax .. bx:
    drawPixel(rgb, x, ay, r, g, b)
    drawPixel(rgb, x, by, r, g, b)
  for y in ay .. by:
    drawPixel(rgb, ax, y, r, g, b)
    drawPixel(rgb, bx, y, r, g, b)

proc drawCross(rgb: var seq[byte]; x, y: int; r, g, b: byte) =
  for d in -3 .. 3:
    drawPixel(rgb, x + d, y, r, g, b)
    drawPixel(rgb, x, y + d, r, g, b)

proc drawLine(rgb: var seq[byte]; x0, y0, x1, y1: int; r, g, b: byte) =
  var x = x0
  var y = y0
  let dx = abs(x1 - x0)
  let sx = if x0 < x1: 1 else: -1
  let dy = -abs(y1 - y0)
  let sy = if y0 < y1: 1 else: -1
  var err = dx + dy

  while true:
    drawPixel(rgb, x, y, r, g, b)
    if x == x1 and y == y1:
      break
    let e2 = 2 * err
    if e2 >= dy:
      err += dy
      x += sx
    if e2 <= dx:
      err += dx
      y += sy

proc writePpm(path: string; rgb: openArray[byte]) =
  var f = open(path, fmWrite)
  defer: f.close()
  f.write(&"P6\n{ModelWidth} {ModelHeight}\n255\n")
  if rgb.len > 0:
    discard f.writeBuffer(unsafeAddr rgb[0], rgb.len)

proc bytesFromString(s: string): seq[byte] =
  result = newSeq[byte](s.len)
  if s.len > 0:
    copyMem(addr result[0], unsafeAddr s[0], s.len)

proc drawPoseOverlay(rgb: var seq[byte]; poses: openArray[PoseDetection]; jointThreshold: float32) =
  for i, pose in poses:
    let x1 = int(pose.bbox.x)
    let y1 = int(pose.bbox.y)
    let x2 = int(pose.bbox.x + pose.bbox.width)
    let y2 = int(pose.bbox.y + pose.bbox.height)

    let r: byte = if i == 0: 255 else: 255
    let g: byte = if i == 0: 0 else: 160
    let b: byte = if i == 0: 0 else: 0
    drawRect(rgb, x1, y1, x2, y2, r, g, b)

    for kp in pose.keypoints:
      if kp.score >= jointThreshold:
        drawCross(rgb, int(kp.x), int(kp.y), 255, 0, 255)

    for pair in Yolov8PoseSkeletonPairs:
      let a = pose.keypoints[pair.a]
      let bkp = pose.keypoints[pair.b]
      if a.score >= jointThreshold and bkp.score >= jointThreshold:
        drawLine(rgb, int(a.x), int(a.y), int(bkp.x), int(bkp.y), 0, 255, 0)

proc main() =
  if paramCount() < 2:
    usage()
    quit 1

  let hefPath = paramStr(1)
  let rawPath = paramStr(2)
  let scoreThreshold = if paramCount() >= 3: parseFloat(paramStr(3)).float32 else: 0.25'f32
  let candidateLimit = if paramCount() >= 4: parseInt(paramStr(4)) else: 100
  let overlayPath = if paramCount() >= 5: paramStr(5) else: ""
  let jointThreshold = if paramCount() >= 6: parseFloat(paramStr(6)).float32 else: 0.5'f32
  let iouThreshold = if paramCount() >= 7: parseFloat(paramStr(7)).float32 else: 0.45'f32
  let maxPoses = if paramCount() >= 8: parseInt(paramStr(8)) else: 20

  let inputStr = readFile(rawPath)
  let expectedInputSize = ModelWidth * ModelHeight * 3
  if inputStr.len != expectedInputSize:
    echo &"input size mismatch: expected={expectedInputSize} actual={inputStr.len}"
    quit 1

  var inputBytes = bytesFromString(inputStr)

  let openRes = MultiOutputInference.open(
    hefPath,
    profiling = true,
    outputFormatType = HAILO_FORMAT_TYPE_FLOAT32
  )
  if openRes.isErr:
    echo "MultiOutputInference.open failed: ", openRes.error
    quit 1

  let model = openRes.get
  var outputs: seq[seq[byte]] = @[]

  let inferRes = model.inferRawInto(inputBytes, outputs)
  if inferRes.isErr:
    echo "inferRawInto failed: ", inferRes.error
    discard model.close()
    quit 1

  let inferResult = inferRes.get
  let config = initYolov8PoseParserConfig(
    inputWidth = ModelWidth,
    inputHeight = ModelHeight,
    scoreThreshold = scoreThreshold,
    jointThreshold = jointThreshold,
    iouThreshold = iouThreshold,
    candidateLimit = candidateLimit,
    maxPoses = maxPoses,
    classId = 0
  )

  var poseResult: PoseResult
  var stats: Yolov8PoseDecodeStats
  let parseRes = parseYolov8PoseInto(model, inferResult, config, poseResult, stats)
  if parseRes.isErr:
    echo "parseYolov8PoseInto failed: ", parseRes.error
    discard model.close()
    quit 1

  echo "YOLOv8 pose probe:"
  echo &"  groups         : {stats.groups}"
  echo &"  scoreThreshold : {scoreThreshold:.5f}"
  echo &"  candidateLimit : {candidateLimit}"
  echo &"  jointThreshold : {jointThreshold:.5f}"
  echo &"  iouThreshold   : {iouThreshold:.5f}"
  echo &"  maxPoses       : {maxPoses}"
  echo &"  raw candidates : {stats.rawCandidates}"
  echo &"  nms input      : {stats.nmsInput}"
  echo &"  poses          : {poseResult.poses.len}"

  for i, pose in poseResult.poses:
    echo &"  pose[{i:02}] score={pose.score:.6f} scale={pose.sourceScale} " &
      &"cell=({pose.cellX},{pose.cellY}) center=({pose.center.x:.1f},{pose.center.y:.1f}) " &
      &"bbox=({pose.bbox.x:.1f},{pose.bbox.y:.1f},{pose.bbox.x + pose.bbox.width:.1f},{pose.bbox.y + pose.bbox.height:.1f}) " &
      &"size=({pose.bbox.width:.1f}x{pose.bbox.height:.1f})"
    for k in 0 ..< PoseKeypointCount:
      let kp = pose.keypoints[k]
      if kp.score >= jointThreshold:
        echo &"    kpt[{k:02}] x={kp.x:.1f} y={kp.y:.1f} score={kp.score:.3f}"

  if overlayPath.len > 0:
    var rgb = inputBytes
    drawPoseOverlay(rgb, poseResult.poses, jointThreshold)
    writePpm(overlayPath, rgb)
    echo "  overlay        : ", overlayPath

  echo "  profile        : ", model.profileSummary()
  discard model.close()

when isMainModule:
  main()
