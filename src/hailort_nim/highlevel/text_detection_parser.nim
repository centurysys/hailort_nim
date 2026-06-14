import std/[algorithm, strformat]

import ./inference_result
import ../lowlevel

# ==============================================================================
# Text detection score-map parser
# ==============================================================================

type
  TextRegionSort* = enum
    ## Sorting strategy for text regions returned by the simple score-map parser.
    trsTopLeft
    trsScoreDesc
    trsAreaDesc

  TextDetectionParserConfig* = object
    ## Simple parser for paddle_ocr_v5_mobile_detection-style UINT8 score maps.
    ##
    ## This is intentionally a pragmatic first parser, not a full DBPostProcess
    ## clone.  It thresholds a 1-channel score map, extracts connected
    ## components, filters very small blobs, optionally expands bboxes with
    ## padding, and returns YOLO-like region records: score + bbox + polygon.
    scoreThreshold*: int
    minScore*: float32
    minArea*: int
    minWidth*: int
    minHeight*: int
    padX*: int
    padY*: int
    maxRegions*: int
    eightConnected*: bool
    sortBy*: TextRegionSort

proc defaultTextDetectionParserConfig*(): TextDetectionParserConfig =
  result = TextDetectionParserConfig(
    scoreThreshold: 128,
    minScore: 0.0'f32,
    minArea: 100,
    minWidth: 8,
    minHeight: 4,
    padX: 0,
    padY: 0,
    maxRegions: 0,
    eightConnected: true,
    sortBy: trsTopLeft
  )

proc initTextDetectionParserConfig*(
  scoreThreshold = 128;
  minScore = 0.0'f32;
  minArea = 100;
  minWidth = 8;
  minHeight = 4;
  padX = 0;
  padY = 0;
  maxRegions = 0;
  eightConnected = true;
  sortBy = trsTopLeft
): TextDetectionParserConfig =
  result = TextDetectionParserConfig(
    scoreThreshold: scoreThreshold,
    minScore: minScore,
    minArea: minArea,
    minWidth: minWidth,
    minHeight: minHeight,
    padX: padX,
    padY: padY,
    maxRegions: maxRegions,
    eightConnected: eightConnected,
    sortBy: sortBy
  )

proc validate*(config: TextDetectionParserConfig): HE[void] =
  if config.scoreThreshold < 0 or config.scoreThreshold > 255:
    return makeError(
      HAILO_INVALID_ARGUMENT,
      &"text scoreThreshold must be in 0..255: {config.scoreThreshold}"
    ).err

  if config.minScore < 0.0'f32 or config.minScore > 1.0'f32:
    return makeError(
      HAILO_INVALID_ARGUMENT,
      &"text minScore must be in 0.0..1.0: {config.minScore}"
    ).err

  if config.minArea < 0:
    return makeError(
      HAILO_INVALID_ARGUMENT,
      &"text minArea must be >= 0: {config.minArea}"
    ).err

  if config.minWidth < 0:
    return makeError(
      HAILO_INVALID_ARGUMENT,
      &"text minWidth must be >= 0: {config.minWidth}"
    ).err

  if config.minHeight < 0:
    return makeError(
      HAILO_INVALID_ARGUMENT,
      &"text minHeight must be >= 0: {config.minHeight}"
    ).err

  if config.padX < 0:
    return makeError(
      HAILO_INVALID_ARGUMENT,
      &"text padX must be >= 0: {config.padX}"
    ).err

  if config.padY < 0:
    return makeError(
      HAILO_INVALID_ARGUMENT,
      &"text padY must be >= 0: {config.padY}"
    ).err

  if config.maxRegions < 0:
    return makeError(
      HAILO_INVALID_ARGUMENT,
      &"text maxRegions must be >= 0: {config.maxRegions}"
    ).err

  result = okVoid()

proc validateTextScoreMap(
  outputPtr: pointer;
  outputSize: int;
  outputMetadata: VStreamMetadata
): HE[void] =
  if outputPtr.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "text score-map output buffer is nil").err

  if outputSize <= 0:
    return makeError(HAILO_INVALID_ARGUMENT, "text score-map output buffer is empty").err

  if outputMetadata.dataType != tdtUint8:
    return makeError(
      HAILO_INVALID_OPERATION,
      &"text score-map output is not UINT8: got {outputMetadata.dataType}"
    ).err

  if outputMetadata.shape.height <= 0 or outputMetadata.shape.width <= 0:
    return makeError(
      HAILO_INVALID_OPERATION,
      &"text score-map shape is invalid: {outputMetadata.shape.height} x {outputMetadata.shape.width} x {outputMetadata.shape.channels}"
    ).err

  if outputMetadata.shape.channels != 1:
    return makeError(
      HAILO_INVALID_OPERATION,
      &"text score-map channels must be 1: got {outputMetadata.shape.channels}"
    ).err

  let expected = outputMetadata.shape.height * outputMetadata.shape.width
  if outputSize < expected:
    return makeError(
      HAILO_INVALID_OPERATION,
      &"text score-map output is smaller than shape: outputSize={outputSize} expected={expected}"
    ).err

  result = okVoid()

proc makeTextRegion(
  minX: int;
  minY: int;
  maxX: int;
  maxY: int;
  area: int;
  scoreSum: uint64;
  imageWidth: int;
  imageHeight: int;
  padX: int;
  padY: int
): TextRegion =
  let score =
    if area > 0:
      float32(float(scoreSum) / (float(area) * 255.0))
    else:
      0.0'f32

  var x0 = max(0, minX - padX)
  var y0 = max(0, minY - padY)
  var x1 = min(imageWidth, maxX + 1 + padX)
  var y1 = min(imageHeight, maxY + 1 + padY)

  if x1 < x0:
    x1 = x0
  if y1 < y0:
    y1 = y0

  result.score = score
  result.area = area
  result.bbox = RectF32(
    x: float32(x0),
    y: float32(y0),
    width: float32(x1 - x0),
    height: float32(y1 - y0)
  )

  let fx0 = float32(x0)
  let fy0 = float32(y0)
  let fx1 = float32(x1)
  let fy1 = float32(y1)
  result.points[0] = PointF32(x: fx0, y: fy0)
  result.points[1] = PointF32(x: fx1, y: fy0)
  result.points[2] = PointF32(x: fx1, y: fy1)
  result.points[3] = PointF32(x: fx0, y: fy1)

proc cmpRegionTopLeft(a, b: TextRegion): int =
  let ay = int(a.bbox.y)
  let by = int(b.bbox.y)
  if ay != by:
    return cmp(ay, by)

  let ax = int(a.bbox.x)
  let bx = int(b.bbox.x)
  if ax != bx:
    return cmp(ax, bx)

  result = cmp(b.area, a.area)

proc cmpRegionScoreDesc(a, b: TextRegion): int =
  if a.score < b.score:
    return 1
  if a.score > b.score:
    return -1
  result = cmpRegionTopLeft(a, b)

proc cmpRegionAreaDesc(a, b: TextRegion): int =
  if a.area != b.area:
    return cmp(b.area, a.area)
  result = cmpRegionTopLeft(a, b)

proc sortTextRegions(regions: var seq[TextRegion]; sortBy: TextRegionSort) =
  case sortBy
  of trsTopLeft:
    regions.sort(cmpRegionTopLeft)
  of trsScoreDesc:
    regions.sort(cmpRegionScoreDesc)
  of trsAreaDesc:
    regions.sort(cmpRegionAreaDesc)

proc parseTextDetectionScoreMapInto*(
  outputPtr: pointer;
  outputSize: int;
  outputMetadata: VStreamMetadata;
  config: TextDetectionParserConfig;
  dst: var TextRegionResult
): HE[void] =
  ## Parse a UINT8 1-channel text score map into YOLO-like text regions.
  ##
  ## Coordinates are in output-map/model-input space.  For the HAILO8L
  ## paddle_ocr_v5_mobile_detection HEF this is expected to be 960x544, i.e.
  ## the same space as the model input image.
  let cfgRes = config.validate()
  if cfgRes.isErr:
    return cfgRes.error.err

  let mapRes = validateTextScoreMap(outputPtr, outputSize, outputMetadata)
  if mapRes.isErr:
    return mapRes.error.err

  dst.regions.setLen(0)

  let width = outputMetadata.shape.width
  let height = outputMetadata.shape.height
  let pixelCount = width * height
  let raw = cast[ptr UncheckedArray[byte]](outputPtr)
  var visited = newSeq[byte](pixelCount)
  var queue = newSeq[int](0)

  for startIdx in 0 ..< pixelCount:
    if visited[startIdx] != 0'u8:
      continue

    if int(raw[startIdx]) < config.scoreThreshold:
      continue

    queue.setLen(0)
    queue.add(startIdx)
    visited[startIdx] = 1'u8

    var head = 0
    var area = 0
    var scoreSum = 0'u64
    var minX = width
    var minY = height
    var maxX = 0
    var maxY = 0

    while head < queue.len:
      let idx = queue[head]
      inc head

      let y = idx div width
      let x = idx - y * width
      let score = raw[idx]

      inc area
      scoreSum += uint64(score)
      if x < minX: minX = x
      if x > maxX: maxX = x
      if y < minY: minY = y
      if y > maxY: maxY = y

      if config.eightConnected:
        for dy in -1 .. 1:
          let ny = y + dy
          if ny < 0 or ny >= height:
            continue

          for dx in -1 .. 1:
            if dx == 0 and dy == 0:
              continue

            let nx = x + dx
            if nx < 0 or nx >= width:
              continue

            let nidx = ny * width + nx
            if visited[nidx] != 0'u8:
              continue

            if int(raw[nidx]) >= config.scoreThreshold:
              visited[nidx] = 1'u8
              queue.add(nidx)
      else:
        const Dirs4 = [(-1, 0), (1, 0), (0, -1), (0, 1)]
        for d in Dirs4:
          let nx = x + d[0]
          let ny = y + d[1]
          if nx < 0 or nx >= width or ny < 0 or ny >= height:
            continue

          let nidx = ny * width + nx
          if visited[nidx] != 0'u8:
            continue

          if int(raw[nidx]) >= config.scoreThreshold:
            visited[nidx] = 1'u8
            queue.add(nidx)

    let bboxW = maxX - minX + 1
    let bboxH = maxY - minY + 1
    let avgScore =
      if area > 0:
        float32(float(scoreSum) / (float(area) * 255.0))
      else:
        0.0'f32

    if area >= config.minArea and
       bboxW >= config.minWidth and
       bboxH >= config.minHeight and
       avgScore >= config.minScore:
      dst.regions.add(
        makeTextRegion(
          minX,
          minY,
          maxX,
          maxY,
          area,
          scoreSum,
          width,
          height,
          config.padX,
          config.padY
        )
      )

  dst.regions.sortTextRegions(config.sortBy)

  if config.maxRegions > 0 and dst.regions.len > config.maxRegions:
    dst.regions.setLen(config.maxRegions)

  result = okVoid()
