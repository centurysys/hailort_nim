when not compileOption("threads"):
  {.warning: "This probe does not require --threads:on, but it is usually built with the same flags as threadtools probes.".}

import std/[algorithm, math, os, strformat, strutils]

import hailort_nim

type
  ScoreCell = object
    outputIndex: int
    outputName: string
    gridH: int
    gridW: int
    row: int
    col: int
    score: float32
    centerX: float32
    centerY: float32
    strideX: float32
    strideY: float32

  ScoreMapSummary = object
    outputIndex: int
    outputName: string
    gridH: int
    gridW: int
    count: int
    zeroCount: int
    nonZeroCount: int
    minScore: float32
    maxScore: float32
    meanScore: float64
    topCells: seq[ScoreCell]

proc usage() =
  echo "Usage: multi_output_pose_score_probe <model.hef> <input.raw> [topN=16] [threshold=0.01] [overlay.ppm]"
  echo ""
  echo "The model is opened with FLOAT32 output vstreams."
  echo "The probe finds FLOAT32 1-channel outputs and prints top scoring cells."
  echo "If overlay.ppm is provided, top cells are drawn on the RGB input image."
  echo ""
  echo "Example:"
  echo "  ./multi_output_pose_score_probe yolov8s_pose.hef pose_test_640x640_rgb.raw 16 0.01 pose_score_overlay.ppm"

proc readFileBytes(path: string): seq[byte] =
  let data = readFile(path)
  result = newSeq[byte](data.len)
  if data.len > 0:
    copyMem(addr result[0], unsafeAddr data[0], data.len)

proc writePpm(path: string; rgb: openArray[byte]; width, height: int) =
  var f = open(path, fmWrite)
  defer: f.close()
  f.write(&"P6\n{width} {height}\n255\n")
  if rgb.len > 0:
    discard f.writeBuffer(unsafeAddr rgb[0], rgb.len)

proc readFloat32LE(data: openArray[byte]; index: int): float32 {.inline.} =
  let pos = index * sizeof(float32)
  if pos < 0 or pos + sizeof(float32) > data.len:
    return 0.0'f32
  copyMem(addr result, unsafeAddr data[pos], sizeof(float32))

proc setPixel(img: var seq[byte]; width, height, x, y: int; r, g, b: byte) {.inline.} =
  if x < 0 or y < 0 or x >= width or y >= height:
    return
  let p = (y * width + x) * 3
  if p < 0 or p + 2 >= img.len:
    return
  img[p + 0] = r
  img[p + 1] = g
  img[p + 2] = b

proc drawLineH(img: var seq[byte]; width, height, x0, x1, y: int; r, g, b: byte) =
  if y < 0 or y >= height:
    return
  let xa = max(0, min(x0, x1))
  let xb = min(width - 1, max(x0, x1))
  if xb < 0 or xa >= width:
    return
  for x in xa .. xb:
    img.setPixel(width, height, x, y, r, g, b)

proc drawLineV(img: var seq[byte]; width, height, x, y0, y1: int; r, g, b: byte) =
  if x < 0 or x >= width:
    return
  let ya = max(0, min(y0, y1))
  let yb = min(height - 1, max(y0, y1))
  if yb < 0 or ya >= height:
    return
  for y in ya .. yb:
    img.setPixel(width, height, x, y, r, g, b)

proc drawRect(img: var seq[byte]; width, height, x0, y0, x1, y1: int; r, g, b: byte; thickness = 1) =
  for t in 0 ..< max(1, thickness):
    img.drawLineH(width, height, x0, x1, y0 + t, r, g, b)
    img.drawLineH(width, height, x0, x1, y1 - t, r, g, b)
    img.drawLineV(width, height, x0 + t, y0, y1, r, g, b)
    img.drawLineV(width, height, x1 - t, y0, y1, r, g, b)

proc drawCross(img: var seq[byte]; width, height, cx, cy, radius: int; r, g, b: byte) =
  img.drawLineH(width, height, cx - radius, cx + radius, cy, r, g, b)
  img.drawLineV(width, height, cx, cy - radius, cy + radius, r, g, b)

proc colorForGrid(gridW: int): tuple[r, g, b: byte] =
  ## RGB colors for visual distinction in PPM overlay.
  ## 80x80: green, 40x40: yellow, 20x20: red, other: cyan.
  case gridW
  of 80:
    (0'u8, 255'u8, 0'u8)
  of 40:
    (255'u8, 255'u8, 0'u8)
  of 20:
    (255'u8, 0'u8, 0'u8)
  else:
    (0'u8, 255'u8, 255'u8)

proc cmpScoreDesc(a, b: ScoreCell): int =
  if a.score > b.score:
    -1
  elif a.score < b.score:
    1
  else:
    cmp(a.outputIndex, b.outputIndex)

proc isFloat32ScoreMap(md: VStreamMetadata; fmt: Format; size: int): bool =
  let expectedSize = md.shape.height * md.shape.width * md.shape.channels * sizeof(float32)
  result =
    md.shape.height > 0 and
    md.shape.width > 0 and
    md.shape.channels == 1 and
    tensorDataType(fmt) == tdtFloat32 and
    expectedSize == size

proc summarizeScoreMap(
  outputIndex: int;
  outputName: string;
  gridH, gridW: int;
  data: openArray[byte];
  inputH, inputW: int;
  topN: int;
  threshold: float32
): ScoreMapSummary =
  result.outputIndex = outputIndex
  result.outputName = outputName
  result.gridH = gridH
  result.gridW = gridW
  result.count = gridH * gridW

  if result.count <= 0:
    return

  let strideX = float32(inputW) / float32(gridW)
  let strideY = float32(inputH) / float32(gridH)
  var initialized = false
  var sum = 0.0
  var candidates: seq[ScoreCell] = @[]

  for row in 0 ..< gridH:
    for col in 0 ..< gridW:
      let idx = row * gridW + col
      let score = readFloat32LE(data, idx)
      if not initialized:
        result.minScore = score
        result.maxScore = score
        initialized = true
      else:
        if score < result.minScore:
          result.minScore = score
        if score > result.maxScore:
          result.maxScore = score

      if score == 0.0'f32:
        inc result.zeroCount
      else:
        inc result.nonZeroCount

      sum += float(score)

      if score >= threshold:
        candidates.add(ScoreCell(
          outputIndex: outputIndex,
          outputName: outputName,
          gridH: gridH,
          gridW: gridW,
          row: row,
          col: col,
          score: score,
          centerX: (float32(col) + 0.5'f32) * strideX,
          centerY: (float32(row) + 0.5'f32) * strideY,
          strideX: strideX,
          strideY: strideY
        ))

  result.meanScore = sum / float(result.count)
  candidates.sort(cmpScoreDesc)
  let keep = min(max(0, topN), candidates.len)
  result.topCells = newSeq[ScoreCell](keep)
  for i in 0 ..< keep:
    result.topCells[i] = candidates[i]

proc overlayTopCells(
  rgbInput: openArray[byte];
  inputW, inputH: int;
  summaries: openArray[ScoreMapSummary]
): seq[byte] =
  result = newSeq[byte](rgbInput.len)
  if rgbInput.len > 0:
    copyMem(addr result[0], unsafeAddr rgbInput[0], rgbInput.len)

  for summary in summaries:
    let color = colorForGrid(summary.gridW)
    for cell in summary.topCells:
      let cx = int(round(cell.centerX))
      let cy = int(round(cell.centerY))
      let halfW = max(2, int(round(float(cell.strideX) / 2.0)))
      let halfH = max(2, int(round(float(cell.strideY) / 2.0)))
      let radius = max(3, min(10, min(halfW, halfH)))
      result.drawRect(inputW, inputH, cx - halfW, cy - halfH, cx + halfW, cy + halfH, color.r, color.g, color.b, 2)
      result.drawCross(inputW, inputH, cx, cy, radius, color.r, color.g, color.b)

proc printMetadata(prefix: string; md: VStreamMetadata; size = -1) =
  echo prefix
  echo &"  name        : {md.name}"
  echo &"  network     : {md.networkName}"
  echo &"  type        : {dataTypeName(md.dataType)}"
  echo &"  pixelFormat : {pixelFormatName(md.pixelFormat)}"
  echo &"  imageType   : {md.imageType}"
  echo &"  flags       : {md.flags}"
  echo &"  shape       : {md.shape}"
  if size >= 0:
    echo &"  frame_size  : {size}"

when isMainModule:
  if paramCount() < 2:
    usage()
    quit 1

  let hefPath = paramStr(1)
  let rawPath = paramStr(2)
  let topN = if paramCount() >= 3: parseInt(paramStr(3)) else: 16
  let threshold = if paramCount() >= 4: parseFloat(paramStr(4)).float32 else: 0.01'f32
  let overlayPath = if paramCount() >= 5: paramStr(5) else: ""

  if topN <= 0:
    echo "topN must be positive"
    quit 1

  let input = readFileBytes(rawPath)

  echo &"hef={hefPath}"
  echo &"raw={rawPath}"
  echo &"input_file_size={input.len}"
  echo &"topN={topN} threshold={threshold:.6g}"
  echo "output_format=FLOAT32"
  if overlayPath.len > 0:
    echo &"overlay={overlayPath}"
  echo ""

  let modelRes = MultiOutputInference.open(
    hefPath,
    profiling = true,
    outputFormatType = HAILO_FORMAT_TYPE_FLOAT32
  )
  if modelRes.isErr:
    echo "MultiOutputInference.open failed: ", modelRes.error
    quit 1

  let model = modelRes.get

  let inputMdRes = model.inputMetadata()
  if inputMdRes.isErr:
    echo "inputMetadata failed: ", inputMdRes.error
    discard model.close()
    quit 1

  let inputMd = inputMdRes.get
  printMetadata("Input metadata:", inputMd, model.inputSize())
  echo ""

  if input.len != model.inputSize():
    echo &"input size mismatch: expected={model.inputSize()} actual={input.len}"
    discard model.close()
    quit 1

  let outputMetasRes = model.outputMetadatas()
  if outputMetasRes.isErr:
    echo "outputMetadatas failed: ", outputMetasRes.error
    discard model.close()
    quit 1

  let outputFormatsRes = model.outputUserFormats()
  if outputFormatsRes.isErr:
    echo "outputUserFormats failed: ", outputFormatsRes.error
    discard model.close()
    quit 1

  let inferRes = model.inferRaw(input)
  if inferRes.isErr:
    echo "inferRaw failed: ", inferRes.error
    discard model.close()
    quit 1

  let outputMetas = outputMetasRes.get
  let outputFormats = outputFormatsRes.get
  let inference = inferRes.get

  echo &"Output vstreams: {model.outputCount()}"
  echo &"Requested output format: {model.requestedOutputFormatName()}"
  echo ""

  var summaries: seq[ScoreMapSummary] = @[]

  for item in inference.outputs:
    let idx = item.index
    if idx < 0 or idx >= outputMetas.len or idx >= outputFormats.len:
      continue

    let md = outputMetas[idx]
    let fmt = outputFormats[idx]
    if isFloat32ScoreMap(md, fmt, item.data.len):
      let summary = summarizeScoreMap(
        idx,
        md.name,
        md.shape.height,
        md.shape.width,
        item.data,
        inputMd.shape.height,
        inputMd.shape.width,
        topN,
        threshold
      )
      summaries.add(summary)

  echo "Pose score map summary:"
  if summaries.len == 0:
    echo "  no FLOAT32 1-channel score maps found"
  for sidx, summary in summaries:
    let strideX = float(inputMd.shape.width) / float(summary.gridW)
    let strideY = float(inputMd.shape.height) / float(summary.gridH)
    echo &"  score_map[{sidx}] output={summary.outputIndex} name={summary.outputName} grid={summary.gridH}x{summary.gridW} stride=({strideX:.3f},{strideY:.3f})"
    echo &"    count={summary.count} min={summary.minScore:.6g} max={summary.maxScore:.6g} mean={summary.meanScore:.6g} zero={summary.zeroCount} nonzero={summary.nonZeroCount} candidates={summary.topCells.len}"
    for i, cell in summary.topCells:
      echo &"    top[{i:02d}] score={cell.score:.6g} cell=({cell.col},{cell.row}) center=({cell.centerX:.1f},{cell.centerY:.1f})"

  if overlayPath.len > 0:
    let expectedRgbSize = inputMd.shape.width * inputMd.shape.height * 3
    if input.len != expectedRgbSize:
      echo &"overlay skipped: input is not RGB24 size expected={expectedRgbSize} actual={input.len}"
    else:
      let overlay = overlayTopCells(input, inputMd.shape.width, inputMd.shape.height, summaries)
      writePpm(overlayPath, overlay, inputMd.shape.width, inputMd.shape.height)
      echo &"overlay: {overlayPath}"

  let closeRes = model.close()
  if closeRes.isErr:
    echo "close failed: ", closeRes.error
    quit 1
