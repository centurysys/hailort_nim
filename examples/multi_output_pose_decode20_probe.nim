import std/[algorithm, math, os, strformat, strutils, times]

import hailort_nim

const
  ModelWidth = 640
  ModelHeight = 640
  RegMax = 15
  RegBins = RegMax + 1
  KptCount = 17

const JointPairs: array[16, tuple[a, b: int]] = [
  (0, 1), (1, 3), (0, 2), (2, 4),
  (5, 6), (5, 7), (7, 9), (6, 8), (8, 10),
  (5, 11), (6, 12), (11, 12),
  (11, 13), (12, 14), (13, 15), (14, 16)
]

type
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
    stride: float32
    bbox: FloatTensorView
    score: FloatTensorView
    kpts: FloatTensorView

  PoseKeypoint = object
    x: float32
    y: float32
    score: float32

  PoseCandidate = object
    score: float32
    scaleIndex: int
    cellX: int
    cellY: int
    centerX: float32
    centerY: float32
    x1: float32
    y1: float32
    x2: float32
    y2: float32
    keypoints: array[KptCount, PoseKeypoint]

proc usage() =
  echo "Usage: multi_output_pose_decode20_probe <model.hef> <input_640x640_rgb.raw> [scoreThreshold] [topN] [overlay.ppm] [jointThreshold]"
  echo "Example:"
  echo "  ./multi_output_pose_decode20_probe yolov8s_pose.hef pose_test_640x640_rgb.raw 0.25 20 pose_decode_overlay.ppm 0.5"

proc clampInt(v, lo, hi: int): int {.inline.} =
  if v < lo: lo elif v > hi: hi else: v

proc clampFloat(v, lo, hi: float32): float32 {.inline.} =
  if v < lo: lo elif v > hi: hi else: v

proc sigmoid(x: float32): float32 {.inline.} =
  if x >= 0'f32:
    let z = exp(-x)
    result = 1'f32 / (1'f32 + z)
  else:
    let z = exp(x)
    result = z / (1'f32 + z)

proc tensorAt(t: FloatTensorView; y, x, ch: int): float32 {.inline.} =
  ## Current HAILO FLOAT32 user buffers for these pose heads are usable as
  ## H x W x C flat tensors in practice, even when metadata order is FCR.
  result = t.data[(y * t.w + x) * t.c + ch]

proc softmaxDflDistance(t: FloatTensorView; y, x, side: int): float32 =
  let base = side * RegBins
  var maxV = t.tensorAt(y, x, base)
  for i in 1 ..< RegBins:
    let v = t.tensorAt(y, x, base + i)
    if v > maxV:
      maxV = v

  var denom = 0'f32
  var numer = 0'f32
  for i in 0 ..< RegBins:
    let e = exp(t.tensorAt(y, x, base + i) - maxV)
    denom += e
    numer += e * float32(i)

  if denom <= 0'f32:
    result = 0'f32
  else:
    result = numer / denom

proc decodeCandidate(group: PoseHeadGroup; scaleIndex, cellY, cellX: int): PoseCandidate =
  let stride = group.stride
  let cx = (float32(cellX) + 0.5'f32) * stride
  let cy = (float32(cellY) + 0.5'f32) * stride

  let left = softmaxDflDistance(group.bbox, cellY, cellX, 0) * stride
  let top = softmaxDflDistance(group.bbox, cellY, cellX, 1) * stride
  let right = softmaxDflDistance(group.bbox, cellY, cellX, 2) * stride
  let bottom = softmaxDflDistance(group.bbox, cellY, cellX, 3) * stride

  result.score = group.score.tensorAt(cellY, cellX, 0)
  result.scaleIndex = scaleIndex
  result.cellX = cellX
  result.cellY = cellY
  result.centerX = cx
  result.centerY = cy
  result.x1 = clampFloat(cx - left, 0'f32, float32(ModelWidth - 1))
  result.y1 = clampFloat(cy - top, 0'f32, float32(ModelHeight - 1))
  result.x2 = clampFloat(cx + right, 0'f32, float32(ModelWidth - 1))
  result.y2 = clampFloat(cy + bottom, 0'f32, float32(ModelHeight - 1))

  for k in 0 ..< KptCount:
    let rawX = group.kpts.tensorAt(cellY, cellX, k * 3 + 0)
    let rawY = group.kpts.tensorAt(cellY, cellX, k * 3 + 1)
    let rawScore = group.kpts.tensorAt(cellY, cellX, k * 3 + 2)
    result.keypoints[k] = PoseKeypoint(
      x: clampFloat(stride * (rawX * 2'f32 - 0.5'f32) + cx, 0'f32, float32(ModelWidth - 1)),
      y: clampFloat(stride * (rawY * 2'f32 - 0.5'f32) + cy, 0'f32, float32(ModelHeight - 1)),
      score: sigmoid(rawScore)
    )

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

proc probeError(status: hailo_status; msg: string): HailoError =
  HailoError(status: status, msg: msg)

proc findTensorViews(model: MultiOutputInference; outputs: seq[MultiOutputInferenceOutput]): HE[seq[FloatTensorView]] =
  let metasRes = model.outputMetadatas()
  if metasRes.isErr:
    return metasRes.error.err
  let metas = metasRes.get

  let fmtsRes = model.outputUserFormats()
  if fmtsRes.isErr:
    return fmtsRes.error.err
  let fmts = fmtsRes.get

  var views: seq[FloatTensorView] = @[]
  for i in 0 ..< outputs.len:
    let meta = metas[i]
    let fmt = fmts[i]
    if fmt.tensorDataType() != tdtFloat32:
      return probeError(HAILO_INVALID_OPERATION, &"output[{i}] is not FLOAT32 user format").err
    if outputs[i].data.len mod sizeof(float32) != 0:
      return probeError(HAILO_INVALID_OPERATION, &"output[{i}] size is not float32-aligned").err

    views.add(FloatTensorView(
      outputIndex: i,
      name: meta.name,
      h: meta.shape.height,
      w: meta.shape.width,
      c: meta.shape.channels,
      data: cast[ptr UncheckedArray[float32]](unsafeAddr outputs[i].data[0]),
      count: outputs[i].data.len div sizeof(float32)
    ))

  result = views.ok

proc findPoseGroups(views: openArray[FloatTensorView]): seq[PoseHeadGroup] =
  for score in views:
    if score.c != 1:
      continue

    var bboxIndex = -1
    var kptIndex = -1
    for i, v in views:
      if v.h == score.h and v.w == score.w and v.c == 64:
        bboxIndex = i
      elif v.h == score.h and v.w == score.w and v.c == 51:
        kptIndex = i

    if bboxIndex >= 0 and kptIndex >= 0:
      result.add(PoseHeadGroup(
        h: score.h,
        w: score.w,
        stride: float32(ModelWidth) / float32(score.w),
        bbox: views[bboxIndex],
        score: score,
        kpts: views[kptIndex]
      ))

  result.sort(proc(a, b: PoseHeadGroup): int = cmp(a.w, b.w))

proc main() =
  if paramCount() < 2:
    usage()
    quit 1

  let hefPath = paramStr(1)
  let rawPath = paramStr(2)
  let scoreThreshold = if paramCount() >= 3: parseFloat(paramStr(3)).float32 else: 0.25'f32
  let topN = if paramCount() >= 4: parseInt(paramStr(4)) else: 20
  let overlayPath = if paramCount() >= 5: paramStr(5) else: ""
  let jointThreshold = if paramCount() >= 6: parseFloat(paramStr(6)).float32 else: 0.5'f32

  let input = readFile(rawPath)
  if input.len != ModelWidth * ModelHeight * 3:
    echo &"input size mismatch: expected={ModelWidth * ModelHeight * 3} actual={input.len}"
    quit 1

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

  let inferRes = model.inferRawInto(cast[seq[byte]](input), outputs)
  if inferRes.isErr:
    echo "inferRawInto failed: ", inferRes.error
    discard model.close()
    quit 1

  let result = inferRes.get
  let viewsRes = findTensorViews(model, result.outputs)
  if viewsRes.isErr:
    echo "findTensorViews failed: ", viewsRes.error
    discard model.close()
    quit 1

  let groups = findPoseGroups(viewsRes.get)
  echo "Pose decode20 probe:"
  echo &"  groups         : {groups.len}"
  echo &"  scoreThreshold : {scoreThreshold:.5f}"
  echo &"  topN           : {topN}"
  echo &"  jointThreshold : {jointThreshold:.5f}"

  var candidates: seq[PoseCandidate] = @[]
  for gi, g in groups:
    var nonzero = 0
    var above = 0
    var maxScore = -Inf.float32
    var maxX = 0
    var maxY = 0
    for y in 0 ..< g.h:
      for x in 0 ..< g.w:
        let s = g.score.tensorAt(y, x, 0)
        if s != 0'f32:
          inc nonzero
        if s > maxScore:
          maxScore = s
          maxX = x
          maxY = y
        if s >= scoreThreshold:
          inc above
          candidates.add(decodeCandidate(g, gi, y, x))

    echo &"  group[{gi}] grid={g.w}x{g.h} stride={g.stride:.1f} " &
      &"bboxOut={g.bbox.outputIndex} scoreOut={g.score.outputIndex} kptOut={g.kpts.outputIndex} " &
      &"nonzero={nonzero} above={above} max={maxScore:.6f} maxCell=({maxX},{maxY})"

  candidates.sort(proc(a, b: PoseCandidate): int = cmp(b.score, a.score))
  if candidates.len > topN:
    candidates.setLen(topN)

  echo &"  candidates     : {candidates.len}"
  for i, c in candidates:
    echo &"  cand[{i:02}] score={c.score:.6f} scale={c.scaleIndex} cell=({c.cellX},{c.cellY}) " &
      &"center=({c.centerX:.1f},{c.centerY:.1f}) " &
      &"bbox=({c.x1:.1f},{c.y1:.1f},{c.x2:.1f},{c.y2:.1f}) " &
      &"size=({c.x2 - c.x1:.1f}x{c.y2 - c.y1:.1f})"
    for k in 0 ..< KptCount:
      let kp = c.keypoints[k]
      if kp.score >= jointThreshold:
        echo &"    kpt[{k:02}] x={kp.x:.1f} y={kp.y:.1f} score={kp.score:.3f}"

  if overlayPath.len > 0:
    var rgb = cast[seq[byte]](input)
    for i, c in candidates:
      let r: byte = if i == 0: 255 else: 255
      let g: byte = if i == 0: 0 else: 160
      let b: byte = if i == 0: 0 else: 0
      drawRect(rgb, int(c.x1), int(c.y1), int(c.x2), int(c.y2), r, g, b)
      for kp in c.keypoints:
        if kp.score >= jointThreshold:
          drawCross(rgb, int(kp.x), int(kp.y), 255, 0, 255)
      for pair in JointPairs:
        let a = c.keypoints[pair.a]
        let bkp = c.keypoints[pair.b]
        if a.score >= jointThreshold and bkp.score >= jointThreshold:
          drawLine(rgb, int(a.x), int(a.y), int(bkp.x), int(bkp.y), 0, 255, 0)
    writePpm(overlayPath, rgb)
    echo "  overlay        : ", overlayPath

  echo "  profile        : ", model.profileSummary()
  discard model.close()

when isMainModule:
  main()
