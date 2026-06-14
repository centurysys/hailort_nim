import std/[algorithm, math, strformat]

import ./inference_result
import ./multi_output_inference
import ../lowlevel

# ==============================================================================
# Public constants and configuration
# ==============================================================================

const
  Yolov8PoseRegMax* = 15
  Yolov8PoseRegBins* = Yolov8PoseRegMax + 1
  Yolov8PoseBoxChannels* = 4 * Yolov8PoseRegBins
  Yolov8PoseKeypointChannels* = PoseKeypointCount * 3

const Yolov8PoseSkeletonPairs*: array[16, tuple[a, b: int]] = [
  (0, 1), (1, 3), (0, 2), (2, 4),
  (5, 6), (5, 7), (7, 9), (6, 8), (8, 10),
  (5, 11), (6, 12), (11, 12),
  (11, 13), (12, 14), (13, 15), (14, 16)
]

type
  Yolov8PoseParserConfig* = object
    ## Parser configuration for YOLOv8 pose heads.
    ##
    ## This parser expects FLOAT32 user output buffers from a multi-output HEF.
    ## The model output should contain, for each grid scale, three tensors:
    ##   - H x W x 64  bbox DFL logits
    ##   - H x W x 1   person/object score
    ##   - H x W x 51  17 keypoints * (x, y, score/logit)
    inputWidth*: int
    inputHeight*: int
    scoreThreshold*: float32
    jointThreshold*: float32
    iouThreshold*: float32
    candidateLimit*: int
    maxPoses*: int
    classId*: int

  Yolov8PoseDecodeStats* = object
    ## Lightweight diagnostics from one parse pass.
    groups*: int
    rawCandidates*: int
    nmsInput*: int
    poses*: int

  FloatTensorView = object
    outputIndex: int
    name: string
    h: int
    w: int
    c: int
    data: ptr UncheckedArray[float32]
    count: int

  PoseHeadGroup = object
    h: int
    w: int
    strideX: float32
    strideY: float32
    bbox: FloatTensorView
    score: FloatTensorView
    kpts: FloatTensorView

# ==============================================================================
# Config helpers
# ==============================================================================

proc initYolov8PoseParserConfig*(
  inputWidth = 640;
  inputHeight = 640;
  scoreThreshold = 0.25'f32;
  jointThreshold = 0.5'f32;
  iouThreshold = 0.45'f32;
  candidateLimit = 100;
  maxPoses = 20;
  classId = 0
): Yolov8PoseParserConfig =
  result.inputWidth = inputWidth
  result.inputHeight = inputHeight
  result.scoreThreshold = scoreThreshold
  result.jointThreshold = jointThreshold
  result.iouThreshold = iouThreshold
  result.candidateLimit = candidateLimit
  result.maxPoses = maxPoses
  result.classId = classId

proc validate*(config: Yolov8PoseParserConfig): HE[void] =
  if config.inputWidth <= 0 or config.inputHeight <= 0:
    return makeError(
      HAILO_INVALID_ARGUMENT,
      &"pose parser input size must be positive: {config.inputWidth}x{config.inputHeight}"
    ).err

  if config.scoreThreshold < 0'f32:
    return makeError(HAILO_INVALID_ARGUMENT, "pose scoreThreshold must be >= 0").err

  if config.jointThreshold < 0'f32:
    return makeError(HAILO_INVALID_ARGUMENT, "pose jointThreshold must be >= 0").err

  if config.iouThreshold < 0'f32 or config.iouThreshold > 1'f32:
    return makeError(HAILO_INVALID_ARGUMENT, "pose iouThreshold must be in [0, 1]").err

  result = okVoid()

# ==============================================================================
# Small math helpers
# ==============================================================================

proc clampFloat(v, lo, hi: float32): float32 {.inline.} =
  if v < lo:
    lo
  elif v > hi:
    hi
  else:
    v

proc sigmoid(x: float32): float32 {.inline.} =
  if x >= 0'f32:
    let z = exp(-x)
    result = 1'f32 / (1'f32 + z)
  else:
    let z = exp(x)
    result = z / (1'f32 + z)

proc tensorAt(t: FloatTensorView; y, x, ch: int): float32 {.inline.} =
  ## HailoRT FLOAT32 user buffers are exposed in a flat H x W x C layout for
  ## this pose model in practice, even when the metadata order is FCR.
  result = t.data[(y * t.w + x) * t.c + ch]

proc softmaxDflDistance(t: FloatTensorView; y, x, side: int): float32 =
  let base = side * Yolov8PoseRegBins
  var maxV = t.tensorAt(y, x, base)
  for i in 1 ..< Yolov8PoseRegBins:
    let v = t.tensorAt(y, x, base + i)
    if v > maxV:
      maxV = v

  var denom = 0'f32
  var numer = 0'f32
  for i in 0 ..< Yolov8PoseRegBins:
    let e = exp(t.tensorAt(y, x, base + i) - maxV)
    denom += e
    numer += e * float32(i)

  if denom <= 0'f32:
    result = 0'f32
  else:
    result = numer / denom

proc bboxArea(p: PoseDetection): float32 {.inline.} =
  result = max(0'f32, p.bbox.width) * max(0'f32, p.bbox.height)

proc bboxIou*(a, b: PoseDetection): float32 =
  let ax2 = a.bbox.x + a.bbox.width
  let ay2 = a.bbox.y + a.bbox.height
  let bx2 = b.bbox.x + b.bbox.width
  let by2 = b.bbox.y + b.bbox.height

  let ix1 = max(a.bbox.x, b.bbox.x)
  let iy1 = max(a.bbox.y, b.bbox.y)
  let ix2 = min(ax2, bx2)
  let iy2 = min(ay2, by2)
  let iw = max(0'f32, ix2 - ix1)
  let ih = max(0'f32, iy2 - iy1)
  let inter = iw * ih
  if inter <= 0'f32:
    return 0'f32

  let unionArea = bboxArea(a) + bboxArea(b) - inter
  if unionArea <= 0'f32:
    result = 0'f32
  else:
    result = inter / unionArea

# ==============================================================================
# Tensor grouping
# ==============================================================================

proc makeTensorViews(
  model: MultiOutputInference;
  outputs: openArray[MultiOutputInferenceOutput]
): HE[seq[FloatTensorView]] =
  if model.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "multi-output inference is nil").err

  let metasRes = model.outputMetadatas()
  if metasRes.isErr:
    return metasRes.error.err
  let metas = metasRes.get

  let fmtsRes = model.outputUserFormats()
  if fmtsRes.isErr:
    return fmtsRes.error.err
  let fmts = fmtsRes.get

  if metas.len != outputs.len or fmts.len != outputs.len:
    return makeError(
      HAILO_INVALID_OPERATION,
      &"output metadata/count mismatch: outputs={outputs.len} metas={metas.len} formats={fmts.len}"
    ).err

  var views: seq[FloatTensorView] = @[]
  for i in 0 ..< outputs.len:
    let meta = metas[i]
    let fmt = fmts[i]
    if fmt.tensorDataType() != tdtFloat32:
      return makeError(
        HAILO_INVALID_OPERATION,
        &"output[{i}] is not FLOAT32 user format; open MultiOutputInference with outputFormatType=HAILO_FORMAT_TYPE_FLOAT32"
      ).err

    if outputs[i].data.len <= 0:
      return makeError(HAILO_INVALID_OPERATION, &"output[{i}] is empty").err

    if outputs[i].data.len mod sizeof(float32) != 0:
      return makeError(HAILO_INVALID_OPERATION, &"output[{i}] size is not float32-aligned").err

    let expected = meta.shape.height * meta.shape.width * meta.shape.channels
    let actual = outputs[i].data.len div sizeof(float32)
    if actual != expected:
      return makeError(
        HAILO_INVALID_OPERATION,
        &"output[{i}] float count mismatch: expected={expected} actual={actual} name={meta.name}"
      ).err

    views.add(FloatTensorView(
      outputIndex: i,
      name: meta.name,
      h: meta.shape.height,
      w: meta.shape.width,
      c: meta.shape.channels,
      data: cast[ptr UncheckedArray[float32]](unsafeAddr outputs[i].data[0]),
      count: actual
    ))

  result = views.ok

proc findPoseHeadGroups(views: openArray[FloatTensorView]; config: Yolov8PoseParserConfig): HE[seq[PoseHeadGroup]] =
  var groups: seq[PoseHeadGroup] = @[]

  for score in views:
    if score.c != 1:
      continue

    var bboxIndex = -1
    var kptIndex = -1
    for i, v in views:
      if v.h == score.h and v.w == score.w and v.c == Yolov8PoseBoxChannels:
        bboxIndex = i
      elif v.h == score.h and v.w == score.w and v.c == Yolov8PoseKeypointChannels:
        kptIndex = i

    if bboxIndex >= 0 and kptIndex >= 0:
      groups.add(PoseHeadGroup(
        h: score.h,
        w: score.w,
        strideX: float32(config.inputWidth) / float32(score.w),
        strideY: float32(config.inputHeight) / float32(score.h),
        bbox: views[bboxIndex],
        score: score,
        kpts: views[kptIndex]
      ))

  groups.sort(proc(a, b: PoseHeadGroup): int = cmp(a.w, b.w))

  if groups.len == 0:
    return makeError(
      HAILO_INVALID_OPERATION,
      "failed to find YOLOv8 pose output groups; expected matching 64ch, 1ch, and 51ch tensors per grid size"
    ).err

  result = groups.ok

# ==============================================================================
# Decode and NMS
# ==============================================================================

proc decodePoseCandidate(
  group: PoseHeadGroup;
  scaleIndex, cellY, cellX: int;
  config: Yolov8PoseParserConfig
): PoseDetection =
  let cx = (float32(cellX) + 0.5'f32) * group.strideX
  let cy = (float32(cellY) + 0.5'f32) * group.strideY

  let left = softmaxDflDistance(group.bbox, cellY, cellX, 0) * group.strideX
  let top = softmaxDflDistance(group.bbox, cellY, cellX, 1) * group.strideY
  let right = softmaxDflDistance(group.bbox, cellY, cellX, 2) * group.strideX
  let bottom = softmaxDflDistance(group.bbox, cellY, cellX, 3) * group.strideY

  let x1 = clampFloat(cx - left, 0'f32, float32(config.inputWidth - 1))
  let y1 = clampFloat(cy - top, 0'f32, float32(config.inputHeight - 1))
  let x2 = clampFloat(cx + right, 0'f32, float32(config.inputWidth - 1))
  let y2 = clampFloat(cy + bottom, 0'f32, float32(config.inputHeight - 1))

  result.score = group.score.tensorAt(cellY, cellX, 0)
  result.classId = config.classId
  result.bbox = RectF32(x: x1, y: y1, width: max(0'f32, x2 - x1), height: max(0'f32, y2 - y1))
  result.center = PointF32(x: cx, y: cy)
  result.sourceScale = scaleIndex
  result.cellX = cellX
  result.cellY = cellY

  for k in 0 ..< PoseKeypointCount:
    let rawX = group.kpts.tensorAt(cellY, cellX, k * 3 + 0)
    let rawY = group.kpts.tensorAt(cellY, cellX, k * 3 + 1)
    let rawScore = group.kpts.tensorAt(cellY, cellX, k * 3 + 2)
    result.keypoints[k] = PoseKeypoint(
      x: clampFloat(group.strideX * (rawX * 2'f32 - 0.5'f32) + cx, 0'f32, float32(config.inputWidth - 1)),
      y: clampFloat(group.strideY * (rawY * 2'f32 - 0.5'f32) + cy, 0'f32, float32(config.inputHeight - 1)),
      score: sigmoid(rawScore)
    )

proc nmsPoseDetections*(
  candidates: openArray[PoseDetection];
  iouThreshold: float32;
  maxPoses: int
): seq[PoseDetection] =
  if candidates.len == 0:
    return @[]

  var sorted = newSeq[PoseDetection](candidates.len)
  for i, c in candidates:
    sorted[i] = c
  sorted.sort(proc(a, b: PoseDetection): int = cmp(b.score, a.score))

  var suppressed = newSeq[bool](sorted.len)
  for i in 0 ..< sorted.len:
    if suppressed[i]:
      continue

    result.add(sorted[i])
    if maxPoses > 0 and result.len >= maxPoses:
      break

    for j in (i + 1) ..< sorted.len:
      if suppressed[j]:
        continue
      if bboxIou(sorted[i], sorted[j]) >= iouThreshold:
        suppressed[j] = true

proc parseYolov8PoseInto*(
  model: MultiOutputInference;
  inferResult: MultiOutputInferenceResult;
  config: Yolov8PoseParserConfig;
  dst: var PoseResult;
  stats: var Yolov8PoseDecodeStats
): HE[void] =
  let validRes = config.validate()
  if validRes.isErr:
    return validRes.error.err

  dst.clear()
  stats = Yolov8PoseDecodeStats()

  let viewsRes = makeTensorViews(model, inferResult.outputs)
  if viewsRes.isErr:
    return viewsRes.error.err

  let groupsRes = findPoseHeadGroups(viewsRes.get, config)
  if groupsRes.isErr:
    return groupsRes.error.err

  let groups = groupsRes.get
  stats.groups = groups.len

  var candidates: seq[PoseDetection] = @[]
  for gi, g in groups:
    for y in 0 ..< g.h:
      for x in 0 ..< g.w:
        let s = g.score.tensorAt(y, x, 0)
        if s >= config.scoreThreshold:
          candidates.add(decodePoseCandidate(g, gi, y, x, config))

  candidates.sort(proc(a, b: PoseDetection): int = cmp(b.score, a.score))
  stats.rawCandidates = candidates.len

  if config.candidateLimit > 0 and candidates.len > config.candidateLimit:
    candidates.setLen(config.candidateLimit)
  stats.nmsInput = candidates.len

  dst.poses = nmsPoseDetections(candidates, config.iouThreshold, config.maxPoses)
  stats.poses = dst.poses.len
  result = okVoid()

proc parseYolov8PoseInto*(
  model: MultiOutputInference;
  inferResult: MultiOutputInferenceResult;
  config: Yolov8PoseParserConfig;
  dst: var PoseResult
): HE[void] =
  var stats: Yolov8PoseDecodeStats
  result = parseYolov8PoseInto(model, inferResult, config, dst, stats)

proc parseYolov8PoseInto*(
  model: MultiOutputInference;
  inferResult: MultiOutputInferenceResult;
  config: Yolov8PoseParserConfig;
  dst: var HailoInferenceResult;
  requestId = 0'u64;
  userData = 0'u64;
  timing = HailoInferenceTiming()
): HE[void] =
  dst.resetKind(hrkPose)
  dst.setCorrelation(requestId, userData)
  dst.timing = timing

  var stats: Yolov8PoseDecodeStats
  let parseRes = parseYolov8PoseInto(model, inferResult, config, dst.pose, stats)
  if parseRes.isErr:
    dst.clear()
    return parseRes.error.err

  result = okVoid()
