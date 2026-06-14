import std/[os, strformat, strutils, monotimes, times]

import hailort_nim
import hailort_nim/highlevel/inference_parser
import hailort_nim/highlevel/inference_result
import hailort_nim/highlevel/threadtools_inference_worker

# ------------------------------------------------------------------------------
# Small helpers
# ------------------------------------------------------------------------------

proc getOrQuit[T](r: HE[T]; label: string): T =
  if r.isErr:
    quit(&"{label} failed: {r.error}", QuitFailure)

  result = r.get

proc quitIfErr(r: HE[void]; label: string) =
  if r.isErr:
    quit(&"{label} failed: {r.error}", QuitFailure)

proc debugTeardown(msg: string) =
  if getEnv("HAILORT_NIM_DEBUG_TEARDOWN") == "1":
    echo msg

proc readFileBytes(path: string): seq[byte] =
  let s = readFile(path)
  result = newSeq[byte](s.len)

  if s.len > 0:
    copyMem(addr result[0], unsafeAddr s[0], s.len)

proc writePpmRgb(path: string; width, height: int; rgb: openArray[byte]) =
  let expected = width * height * 3
  if rgb.len != expected:
    quit(&"overlay input size mismatch: expected={expected} actual={rgb.len}", QuitFailure)

  var f = open(path, fmWrite)
  defer: f.close()
  f.write(&"P6\n{width} {height}\n255\n")
  if rgb.len > 0:
    discard f.writeBuffer(unsafeAddr rgb[0], rgb.len)

proc setPixelRgb(
  img: var seq[byte];
  width, height: int;
  x, y: int;
  r, g, b: byte
) {.inline.} =
  if x < 0 or x >= width or y < 0 or y >= height:
    return

  let off = (y * width + x) * 3
  img[off + 0] = r
  img[off + 1] = g
  img[off + 2] = b

proc drawRectRgb(
  img: var seq[byte];
  width, height: int;
  region: TextRegion;
  thickness = 2
) =
  var x0 = int(region.bbox.x)
  var y0 = int(region.bbox.y)
  var x1 = int(region.bbox.x + region.bbox.width) - 1
  var y1 = int(region.bbox.y + region.bbox.height) - 1

  x0 = max(0, min(width - 1, x0))
  y0 = max(0, min(height - 1, y0))
  x1 = max(0, min(width - 1, x1))
  y1 = max(0, min(height - 1, y1))

  if x1 < x0 or y1 < y0:
    return

  let t = max(1, thickness)
  for k in 0 ..< t:
    for x in x0 .. x1:
      setPixelRgb(img, width, height, x, y0 + k, 255'u8, 0'u8, 0'u8)
      setPixelRgb(img, width, height, x, y1 - k, 255'u8, 0'u8, 0'u8)
    for y in y0 .. y1:
      setPixelRgb(img, width, height, x0 + k, y, 255'u8, 0'u8, 0'u8)
      setPixelRgb(img, width, height, x1 - k, y, 255'u8, 0'u8, 0'u8)

proc writeOverlayPpm(
  path: string;
  width, height: int;
  inputRgb: openArray[byte];
  regions: openArray[TextRegion]
) =
  var overlay = newSeq[byte](inputRgb.len)
  if inputRgb.len > 0:
    copyMem(addr overlay[0], unsafeAddr inputRgb[0], inputRgb.len)

  for region in regions:
    overlay.drawRectRgb(width, height, region, thickness = 2)

  writePpmRgb(path, width, height, overlay)

proc usage() =
  echo "Usage: threadtools_text_detection_probe <hef> <rgb-raw-input> [loops] [slots] [queue] [threshold] [min-area] [min-width] [min-height] [overlay-ppm] [pad-x] [pad-y] [max-regions]"
  echo ""
  echo "This probe runs ThreadtoolsInferenceWorker with the simple TextDetection parser."
  echo "It expects RGB24 raw input matching the model input size.  If overlay-ppm is"
  echo "given, detected YOLO-like text bboxes are drawn on the input image and written as a PPM file."
  echo ""
  echo "Example:"
  echo "  threadtools_text_detection_probe paddle_ocr_v5_mobile_detection.hef test_detection_960x544_rgb.raw 10 2 4 128 500 8 4 overlay.ppm 6 8 0"

# ------------------------------------------------------------------------------
# main
# ------------------------------------------------------------------------------

proc main() =
  if paramCount() < 2:
    usage()
    quit(QuitFailure)

  let hefPath = paramStr(1)
  let rawPath = paramStr(2)
  let loops =
    if paramCount() >= 3:
      parseInt(paramStr(3))
    else:
      10
  let slots =
    if paramCount() >= 4:
      parseInt(paramStr(4))
    else:
      2
  let queueSize =
    if paramCount() >= 5:
      parseInt(paramStr(5))
    else:
      recommendedThreadtoolsInferenceWorkerRequestQueueSize(slots)
  let threshold =
    if paramCount() >= 6:
      parseInt(paramStr(6))
    else:
      128
  let minArea =
    if paramCount() >= 7:
      parseInt(paramStr(7))
    else:
      100
  let minWidth =
    if paramCount() >= 8:
      parseInt(paramStr(8))
    else:
      8
  let minHeight =
    if paramCount() >= 9:
      parseInt(paramStr(9))
    else:
      4
  let overlayPath =
    if paramCount() >= 10:
      paramStr(10)
    else:
      ""
  let padX =
    if paramCount() >= 11:
      parseInt(paramStr(11))
    else:
      6
  let padY =
    if paramCount() >= 12:
      parseInt(paramStr(12))
    else:
      8
  let maxRegions =
    if paramCount() >= 13:
      parseInt(paramStr(13))
    else:
      0

  if loops <= 0:
    quit("loops must be positive", QuitFailure)
  if slots <= 0:
    quit("slots must be positive", QuitFailure)
  if queueSize <= 0:
    quit("queue size must be positive", QuitFailure)

  let inputTemplate = readFileBytes(rawPath)
  let det = getOrQuit(Detector.open(hefPath), "Detector.open")
  let inputMeta = getOrQuit(det.inputMetadata(), "Detector.inputMetadata")

  if inputTemplate.len != det.inputSize():
    quit(
      &"input size mismatch: expected={det.inputSize()} actual={inputTemplate.len}",
      QuitFailure
    )

  if overlayPath.len > 0:
    if inputMeta.shape.channels != 3:
      quit(
        &"overlay output requires RGB input with 3 channels: got {inputMeta.shape.channels}",
        QuitFailure
      )

  let parserConfig = initTextDetectionDbParserConfig(
    scoreThreshold = threshold,
    minArea = minArea,
    minWidth = minWidth,
    minHeight = minHeight,
    padX = padX,
    padY = padY,
    maxRegions = maxRegions,
    sortBy = trsTopLeft
  )
  let worker = getOrQuit(
    det.startThreadtoolsInferenceWorker(parserConfig, slots, queueSize),
    "startThreadtoolsInferenceWorker"
  )

  let outputMeta = worker.outputMetadata()

  echo &"hef={hefPath}"
  echo &"raw={rawPath}"
  echo &"input_size={worker.inputSize()} output_size={worker.outputSize()}"
  echo &"loops={loops} slots={slots} queue={queueSize}"
  echo &"parser=text_detection threshold={threshold} minArea={minArea} minWidth={minWidth} minHeight={minHeight} padX={padX} padY={padY} maxRegions={maxRegions}"
  if overlayPath.len > 0:
    echo &"overlay={overlayPath}"
  echo ""
  echo "Input metadata:"
  echo &"  shape       : {inputMeta.shape.height} x {inputMeta.shape.width} x {inputMeta.shape.channels}"
  echo "Output metadata:"
  echo &"  name        : {outputMeta.name}"
  echo &"  network     : {outputMeta.networkName}"
  echo &"  type        : {outputMeta.dataType}"
  echo &"  pixelFormat : {outputMeta.pixelFormat}"
  echo &"  imageType   : {outputMeta.imageType}"
  echo &"  shape       : {outputMeta.shape.height} x {outputMeta.shape.width} x {outputMeta.shape.channels}"

  let initial = min(loops, queueSize)
  var submitted = 0
  var completed = 0

  var totalWriteUs: int64 = 0
  var totalReadUs: int64 = 0
  var totalParseUs: int64 = 0
  var minWaitUs: int64 = high(int64)
  var maxWaitUs: int64 = 0
  var lastRequestId: uint64 = 0'u64
  var lastUserData: uint64 = 0'u64
  var lastRegions: seq[TextRegion] = @[]

  const userDataBase = 40_000'u64

  let started = getMonoTime()

  for _ in 0 ..< initial:
    quitIfErr(
      worker.submitCopy(
        inputTemplate,
        uint64(submitted),
        userDataBase + uint64(submitted)
      ),
      "submitCopy"
    )
    inc submitted

  while completed < loops:
    var reply: ThreadtoolsInferenceWorkerReply
    let waitStarted = getMonoTime()
    quitIfErr(worker.waitReply(reply), "waitReply")
    let waitUs = inMicroseconds(getMonoTime() - waitStarted)

    case reply.kind
    of tiwrkError:
      let err = reply.error.toHailoError()
      quit(&"worker request {reply.requestId} failed: {err}", QuitFailure)
    of tiwrkResult:
      let expectedUserData = userDataBase + reply.requestId
      if reply.userData != expectedUserData:
        quit(
          &"worker request {reply.requestId} returned unexpected userData: expected={expectedUserData} actual={reply.userData}",
          QuitFailure
        )
      if reply.result.inference.kind != hrkTextRegions:
        quit(
          &"worker request {reply.requestId} returned unexpected kind: {reply.result.inference.kind}",
          QuitFailure
        )

      lastRequestId = reply.requestId
      lastUserData = reply.userData

      let timing = reply.result.inference.timing
      totalWriteUs += timing.writeUs
      totalReadUs += timing.readUs
      totalParseUs += timing.parseUs

      lastRegions.setLen(0)
      for region in reply.result.inference.textRegions.regions:
        lastRegions.add(region)
      reply.clear()

      if waitUs < minWaitUs:
        minWaitUs = waitUs
      if waitUs > maxWaitUs:
        maxWaitUs = waitUs

      inc completed

      if submitted < loops:
        quitIfErr(
          worker.submitCopy(
            inputTemplate,
            uint64(submitted),
            userDataBase + uint64(submitted)
          ),
          "submitCopy"
        )
        inc submitted

  let elapsedUs = inMicroseconds(getMonoTime() - started)
  quitIfErr(worker.stop(), "worker.stop")
  quitIfErr(worker.join(), "worker.join")

  let elapsedMs = float(elapsedUs) / 1000.0
  let fps =
    if elapsedUs > 0:
      float(loops) * 1_000_000.0 / float(elapsedUs)
    else:
      0.0

  echo ""
  echo "Threadtools text detection summary:"
  echo &"  elapsed    : {elapsedMs:.3f} ms"
  echo &"  fps        : {fps:.2f}"
  echo &"  avg write  : {float(totalWriteUs) / float(loops) / 1000.0:.3f} ms"
  echo &"  avg read   : {float(totalReadUs) / float(loops) / 1000.0:.3f} ms"
  echo &"  avg parse  : {float(totalParseUs) / float(loops) / 1000.0:.3f} ms"
  echo &"  wait min   : {float(minWaitUs) / 1000.0:.3f} ms"
  echo &"  wait max   : {float(maxWaitUs) / 1000.0:.3f} ms"
  echo &"  last req   : {lastRequestId}"
  echo &"  last data  : {lastUserData}"
  echo &"  regions    : {lastRegions.len}"

  let yoloDetections = lastRegions.toDetections(inputMeta.shape.width, inputMeta.shape.height, classId = 0)
  echo &"  yolo_like  : {yoloDetections.len}"

  for i, r in lastRegions:
    let d = yoloDetections[i]
    echo &"  region[{i:02}] score={r.score:.3f} area={r.area} bbox=({r.bbox.x:.1f},{r.bbox.y:.1f},{r.bbox.width:.1f},{r.bbox.height:.1f}) norm=({d.xMin:.4f},{d.yMin:.4f},{d.xMax:.4f},{d.yMax:.4f})"

  if overlayPath.len > 0:
    writeOverlayPpm(
      overlayPath,
      inputMeta.shape.width,
      inputMeta.shape.height,
      inputTemplate,
      lastRegions
    )
    echo &"  overlay    : {overlayPath}"

  debugTeardown("teardown: before worker.close")
  if not worker.isClosed():
    quitIfErr(worker.close(), "worker.close")
  debugTeardown("teardown: after worker.close")

  debugTeardown("teardown: before Detector.close")
  quitIfErr(det.close(), "Detector.close")
  debugTeardown("teardown: after Detector.close")

  debugTeardown("teardown: leaving main")

# ------------------------------------------------------------------------------
# isMainModule
# ------------------------------------------------------------------------------

when isMainModule:
  main()
