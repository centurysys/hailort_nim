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

proc previewBytes(bytes: var RawTensorBytes; maxCount: int): string =
  let n = min(bytes.len, max(0, maxCount))
  var parts: seq[string] = @[]
  for i in 0 ..< n:
    parts.add(toHex(int(bytes.byteAt(i)), 2))

  result = parts.join(" ")

proc usage() =
  echo "Usage: threadtools_inference_worker_raw_probe <hef> <raw-input> [loops] [slots] [queue] [max-raw-bytes] [preview-bytes]"
  echo ""
  echo "This probe runs ThreadtoolsInferenceWorker with RawTensorParser."
  echo "The output tensor is copied into RawTensorResult so it remains valid after"
  echo "the vstream slot is released."
  echo ""
  echo "Example:"
  echo "  threadtools_inference_worker_raw_probe paddle_ocr_v5_mobile_detection.hef input.raw 10 2 4 0 64"

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
  let maxRawBytes =
    if paramCount() >= 6:
      parseInt(paramStr(6))
    else:
      0
  let previewCount =
    if paramCount() >= 7:
      parseInt(paramStr(7))
    else:
      64

  if loops <= 0:
    quit("loops must be positive", QuitFailure)
  if slots <= 0:
    quit("slots must be positive", QuitFailure)
  if queueSize <= 0:
    quit("queue size must be positive", QuitFailure)
  if maxRawBytes < 0:
    quit("max-raw-bytes must be >= 0", QuitFailure)
  if previewCount < 0:
    quit("preview-bytes must be >= 0", QuitFailure)

  if queueSize <= slots:
    echo &"note: queue={queueSize} <= slots={slots}; this benchmark may underfill HAILO. Use queue >= {slots * 2}."

  let inputTemplate = readFileBytes(rawPath)
  let det = getOrQuit(Detector.open(hefPath), "Detector.open")

  if inputTemplate.len != det.inputSize():
    quit(
      &"input size mismatch: expected={det.inputSize()} actual={inputTemplate.len}",
      QuitFailure
    )

  let parserConfig = initRawTensorParserConfig(maxRawTensorBytes = maxRawBytes)
  let worker = getOrQuit(
    det.startThreadtoolsInferenceWorker(parserConfig, slots, queueSize),
    "startThreadtoolsInferenceWorker"
  )

  let outputMeta = worker.outputMetadata()

  echo &"hef={hefPath}"
  echo &"raw={rawPath}"
  echo &"input_size={worker.inputSize()} output_size={worker.outputSize()}"
  echo &"loops={loops} slots={slots} queue={queueSize} max_raw_bytes={maxRawBytes}"
  echo "parser=raw_tensor"
  echo ""
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
  var lastOutputName = ""
  var lastOutputSize = 0
  var lastPreview = ""

  const userDataBase = 30_000'u64

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
      if reply.result.userData != reply.userData:
        quit(
          &"worker request {reply.requestId} result userData mismatch: reply={reply.userData} result={reply.result.userData}",
          QuitFailure
        )
      if reply.result.inference.kind != hrkRawTensor:
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

      if reply.result.inference.raw.outputName.len > 0:
        lastOutputName = reply.result.inference.raw.outputName
      else:
        lastOutputName = outputMeta.name
      lastOutputSize = reply.result.inference.raw.outputSize
      lastPreview = previewBytes(reply.result.inference.raw.bytes, previewCount)
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
  echo "Threadtools inference worker raw summary:"
  echo &"  elapsed    : {elapsedMs:.3f} ms"
  echo &"  fps        : {fps:.2f}"
  echo &"  avg write  : {float(totalWriteUs) / float(loops) / 1000.0:.3f} ms"
  echo &"  avg read   : {float(totalReadUs) / float(loops) / 1000.0:.3f} ms"
  echo &"  avg parse  : {float(totalParseUs) / float(loops) / 1000.0:.3f} ms"
  echo &"  wait min   : {float(minWaitUs) / 1000.0:.3f} ms"
  echo &"  wait max   : {float(maxWaitUs) / 1000.0:.3f} ms"
  echo &"  last req   : {lastRequestId}"
  echo &"  last data  : {lastUserData}"
  echo &"  raw name   : {lastOutputName}"
  echo &"  raw size   : {lastOutputSize}"
  echo &"  raw preview: {lastPreview}"

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
