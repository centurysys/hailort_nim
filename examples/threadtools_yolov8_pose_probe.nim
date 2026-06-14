import std/[os, strformat, strutils]

import hailort_nim

const
  ModelWidth = 640
  ModelHeight = 640

proc usage() =
  echo "Usage: threadtools_yolov8_pose_probe <model.hef> <input_640x640_rgb.raw> [loops] [scoreThreshold] [candidateLimit] [overlay.ppm] [jointThreshold] [iouThreshold] [maxPoses]"
  echo "Example:"
  echo "  ./threadtools_yolov8_pose_probe yolov8s_pose.hef pose_test_640x640_rgb.raw 10 0.25 100 pose_worker_overlay.ppm 0.5 0.45 20"

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
  let loops = if paramCount() >= 3: parseInt(paramStr(3)) else: 10
  let scoreThreshold = if paramCount() >= 4: parseFloat(paramStr(4)).float32 else: 0.25'f32
  let candidateLimit = if paramCount() >= 5: parseInt(paramStr(5)) else: 100
  let overlayPath = if paramCount() >= 6: paramStr(6) else: ""
  let jointThreshold = if paramCount() >= 7: parseFloat(paramStr(7)).float32 else: 0.5'f32
  let iouThreshold = if paramCount() >= 8: parseFloat(paramStr(8)).float32 else: 0.45'f32
  let maxPoses = if paramCount() >= 9: parseInt(paramStr(9)) else: 20

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
  let poseConfig = initYolov8PoseParserConfig(
    inputWidth = ModelWidth,
    inputHeight = ModelHeight,
    scoreThreshold = scoreThreshold,
    jointThreshold = jointThreshold,
    iouThreshold = iouThreshold,
    candidateLimit = candidateLimit,
    maxPoses = maxPoses,
    classId = 0
  )
  let workerConfig = initThreadtoolsYolov8PoseWorkerConfig(
    slotCount = 1,
    poseConfig = poseConfig
  )

  let workerRes = model.startThreadtoolsMultiOutputInferenceWorker(workerConfig)
  if workerRes.isErr:
    echo "startThreadtoolsMultiOutputInferenceWorker failed: ", workerRes.error
    discard model.close()
    quit 1

  let worker = workerRes.get

  var lastReply: ThreadtoolsMultiOutputInferenceWorkerReply
  var lastStats: Yolov8PoseDecodeStats
  var okReplies = 0
  var errorReplies = 0
  var totalWriteUs: int64 = 0
  var totalReadUs: int64 = 0
  var totalParseUs: int64 = 0
  var lastRequestId: uint64 = 0
  var lastUserData: uint64 = 0

  # Do not enqueue all requests before receiving replies.  With small request and
  # reply queues, that can create a normal back-pressure deadlock: the main
  # thread blocks on submit while the worker blocks on sending replies.  Keep a
  # bounded number of in-flight requests and receive as we go.
  let maxInflight = max(1, min(workerConfig.requestQueueSize, max(1, loops)))
  var submitted = 0
  var received = 0

  while received < loops:
    while submitted < loops and (submitted - received) < maxInflight:
      let submitRes = worker.submitCopy(
        inputBytes,
        requestId = uint64(submitted),
        userData = uint64(50000 + submitted)
      )
      if submitRes.isErr:
        echo "submit failed: ", submitRes.error
        discard worker.close()
        quit 1
      inc submitted

    lastReply.clear()
    let recvRes = worker.waitReply(lastReply)
    if recvRes.isErr:
      echo "waitReply failed: ", recvRes.error
      discard worker.close()
      quit 1

    inc received

    case lastReply.kind
    of tmowrkError:
      inc errorReplies
      echo &"reply error requestId={lastReply.requestId} status={lastReply.error.status} msg={lastReply.error.msg}"
    of tmowrkResult:
      inc okReplies
      let infp = addr lastReply.result.inference
      totalWriteUs += infp[].timing.writeUs
      totalReadUs += infp[].timing.readUs
      totalParseUs += infp[].timing.parseUs
      lastRequestId = lastReply.result.requestId
      lastUserData = lastReply.result.userData
      lastStats = lastReply.result.poseStats

  let denom = max(1, okReplies)
  echo "Threadtools YOLOv8 pose worker summary:"
  echo &"  loops          : {loops}"
  echo &"  max in-flight  : {maxInflight}"
  echo &"  ok replies     : {okReplies}"
  echo &"  error replies  : {errorReplies}"
  echo &"  scoreThreshold : {scoreThreshold:.5f}"
  echo &"  candidateLimit : {candidateLimit}"
  echo &"  jointThreshold : {jointThreshold:.5f}"
  echo &"  iouThreshold   : {iouThreshold:.5f}"
  echo &"  maxPoses       : {maxPoses}"
  echo &"  avg write      : {float(totalWriteUs) / float(denom) / 1000.0:.3f} ms"
  echo &"  avg read       : {float(totalReadUs) / float(denom) / 1000.0:.3f} ms"
  echo &"  avg parse      : {float(totalParseUs) / float(denom) / 1000.0:.3f} ms"
  echo &"  last req       : {lastRequestId}"
  echo &"  last data      : {lastUserData}"
  echo &"  groups         : {lastStats.groups}"
  echo &"  raw candidates : {lastStats.rawCandidates}"
  echo &"  nms input      : {lastStats.nmsInput}"
  let finalInfp = addr lastReply.result.inference
  let finalPoseCount =
    if lastReply.kind == tmowrkResult:
      finalInfp[].pose.poses.len
    else:
      0
  echo &"  poses          : {finalPoseCount}"

  if lastReply.kind == tmowrkResult:
    for i, pose in finalInfp[].pose.poses:
      echo &"  pose[{i:02}] score={pose.score:.6f} scale={pose.sourceScale} " &
        &"cell=({pose.cellX},{pose.cellY}) center=({pose.center.x:.1f},{pose.center.y:.1f}) " &
        &"bbox=({pose.bbox.x:.1f},{pose.bbox.y:.1f},{pose.bbox.x + pose.bbox.width:.1f},{pose.bbox.y + pose.bbox.height:.1f}) " &
        &"size=({pose.bbox.width:.1f}x{pose.bbox.height:.1f})"

  if overlayPath.len > 0:
    var rgb = inputBytes
    if lastReply.kind == tmowrkResult:
      drawPoseOverlay(rgb, finalInfp[].pose.poses, jointThreshold)
    writePpm(overlayPath, rgb)
    echo "  overlay        : ", overlayPath

  echo "  profile        : ", worker.profileSummary()

  # Drop the last moved reply payload before closing the worker/HAILO objects.
  # This follows the same ownership pattern used by the raw-tensor probes: the
  # caller consumes the reply, then clears it explicitly instead of leaving a
  # cross-thread moved payload to be finalized during process teardown.
  lastReply.clear()

  let closeRes = worker.close()
  if closeRes.isErr:
    echo "worker.close failed: ", closeRes.error
    quit 1

when isMainModule:
  main()
