import std/[math, os, strformat]
import pixie
import hailort_nim

const
  ModelW = 640
  ModelH = 640
  JointThreshold = 0.5'f32

type Letterbox = object
  scale: float32
  padX, padY: float32

proc fail(msg: string) =
  quit msg, 1

proc clampf(v, lo, hi: float32): float32 =
  max(lo, min(hi, v))

proc toModelImage(src: Image; lb: var Letterbox): Image =
  let sx = ModelW.float32 / src.width.float32
  let sy = ModelH.float32 / src.height.float32
  lb.scale = min(sx, sy)

  let rw = src.width.float32 * lb.scale
  let rh = src.height.float32 * lb.scale
  lb.padX = (ModelW.float32 - rw) / 2
  lb.padY = (ModelH.float32 - rh) / 2

  result = newImage(ModelW, ModelH)
  result.fill(rgba(114, 114, 114, 255))
  newContext(result).drawImage(src, lb.padX, lb.padY, rw, rh)

proc toRgbBytes(image: Image): seq[byte] =
  result = newSeq[byte](ModelW * ModelH * 3)
  for y in 0 ..< ModelH:
    for x in 0 ..< ModelW:
      let c = image[x, y]
      let i = (y * ModelW + x) * 3
      result[i + 0] = c.r
      result[i + 1] = c.g
      result[i + 2] = c.b

proc mapX(lb: Letterbox; x: float32): float32 = (x - lb.padX) / lb.scale
proc mapY(lb: Letterbox; y: float32): float32 = (y - lb.padY) / lb.scale

proc drawPoses(image: Image; poses: openArray[PoseDetection]; lb: Letterbox) =
  let ctx = newContext(image)
  for pose in poses:
    let x1 = clampf(lb.mapX(pose.bbox.x), 0, image.width.float32 - 1)
    let y1 = clampf(lb.mapY(pose.bbox.y), 0, image.height.float32 - 1)
    let x2 = clampf(lb.mapX(pose.bbox.x + pose.bbox.width), 0, image.width.float32 - 1)
    let y2 = clampf(lb.mapY(pose.bbox.y + pose.bbox.height), 0, image.height.float32 - 1)

    ctx.lineWidth = 3
    ctx.strokeStyle = "#ff3333"
    ctx.strokeRect(x1, y1, x2 - x1, y2 - y1)

    ctx.lineWidth = 2
    ctx.strokeStyle = "#00dd55"
    for e in Yolov8PoseSkeletonPairs:
      let a = pose.keypoints[e.a]
      let b = pose.keypoints[e.b]
      if a.score >= JointThreshold and b.score >= JointThreshold:
        ctx.strokeSegment(lb.mapX(a.x), lb.mapY(a.y), lb.mapX(b.x), lb.mapY(b.y))

    ctx.fillStyle = "#ff00ff"
    for kp in pose.keypoints:
      if kp.score >= JointThreshold:
        let x = lb.mapX(kp.x)
        let y = lb.mapY(kp.y)
        ctx.fillRect(x - 2, y - 2, 4, 4)

proc main() =
  if paramCount() != 3:
    fail "Usage: threadtools_yolov8_pose_minimal_pixie <yolov8s_pose.hef> <image.png|jpg> <overlay.png>"

  var src = readImage(paramStr(2))
  var lb: Letterbox
  let modelImage = src.toModelImage(lb)
  let input = modelImage.toRgbBytes()

  let modelRes = MultiOutputInference.open(
    paramStr(1),
    profiling = true,
    outputFormatType = HAILO_FORMAT_TYPE_FLOAT32
  )
  if modelRes.isErr: fail $modelRes.error

  let model = modelRes.get
  let poseCfg = initYolov8PoseParserConfig(inputWidth = ModelW, inputHeight = ModelH)
  let workerCfg = initThreadtoolsYolov8PoseWorkerConfig(slotCount = 1, poseConfig = poseCfg)
  let workerRes = model.startThreadtoolsMultiOutputInferenceWorker(workerCfg)
  if workerRes.isErr: fail $workerRes.error

  let worker = workerRes.get
  var reply: ThreadtoolsMultiOutputInferenceWorkerReply

  let sendRes = worker.submitCopy(input, requestId = 1, userData = 0)
  if sendRes.isErr: fail $sendRes.error

  let recvRes = worker.waitReply(reply)
  if recvRes.isErr: fail $recvRes.error
  if reply.kind == tmowrkError:
    fail &"worker error: {reply.error.status} {reply.error.msg}"

  let inf = addr reply.result.inference
  echo &"poses={inf[].pose.poses.len} parse_ms={inf[].timing.parseUs.float / 1000.0:.3f}"
  src.drawPoses(inf[].pose.poses, lb)
  src.writeFile(paramStr(3))
  echo &"wrote {paramStr(3)}"

  reply.clear()
  let closeRes = worker.close()
  if closeRes.isErr: fail $closeRes.error

main()
