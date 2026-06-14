import std/[os, strformat, strutils, monotimes, times]

import hailort_nim
import hailort_nim/highlevel/threadtools_detector_worker

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

proc readFileBytes(path: string): seq[byte] =
  let s = readFile(path)
  result = newSeq[byte](s.len)

  if s.len > 0:
    copyMem(addr result[0], unsafeAddr s[0], s.len)

proc usage() =
  echo "Usage: threadtools_detector_worker_probe <hef> <raw-input> [loops] [slots] [queue] [score-threshold]"
  echo ""
  echo "Example:"
  echo "  threadtools_detector_worker_probe yolov11n.hef dog_640x640x3.raw 100 2 2 0.25"

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
      100
  let slots =
    if paramCount() >= 4:
      parseInt(paramStr(4))
    else:
      2
  let queueSize =
    if paramCount() >= 5:
      parseInt(paramStr(5))
    else:
      2
  let threshold =
    if paramCount() >= 6:
      parseFloat(paramStr(6)).float32
    else:
      0.25'f32

  if loops <= 0:
    quit("loops must be positive", QuitFailure)
  if queueSize <= 0:
    quit("queue size must be positive", QuitFailure)

  let inputTemplate = readFileBytes(rawPath)
  let det = getOrQuit(Detector.open(hefPath), "Detector.open")
  defer:
    discard det.close()

  if inputTemplate.len != det.inputSize():
    quit(
      &"input size mismatch: expected={det.inputSize()} actual={inputTemplate.len}",
      QuitFailure
    )

  let worker = getOrQuit(
    det.startThreadtoolsDetectorWorker(slots, queueSize),
    "startThreadtoolsDetectorWorker"
  )
  defer:
    discard worker.close()

  echo &"hef={hefPath}"
  echo &"raw={rawPath}"
  echo &"input_size={worker.inputSize()} output_size={worker.outputSize()}"
  echo &"loops={loops} slots={slots} queue={queueSize} threshold={threshold:.3f}"

  let initial = min(loops, queueSize)
  var submitted = 0
  var completed = 0

  var totalWriteUs: int64 = 0
  var totalReadUs: int64 = 0
  var totalParseUs: int64 = 0
  var totalSortUs: int64 = 0
  var minWaitUs: int64 = high(int64)
  var maxWaitUs: int64 = 0
  var lastDetectionCount = 0
  var lastTop: Detection
  var hasTop = false

  let started = getMonoTime()

  for _ in 0 ..< initial:
    quitIfErr(
      worker.submitCopy(inputTemplate, uint64(submitted), threshold),
      "submitCopy"
    )
    inc submitted

  while completed < loops:
    var reply: ThreadtoolsDetectorWorkerReply
    let waitStarted = getMonoTime()
    quitIfErr(worker.waitReply(reply), "waitReply")
    let waitUs = inMicroseconds(getMonoTime() - waitStarted)

    case reply.kind
    of tdwrkError:
      let err = reply.error.toHailoError()
      quit(&"worker request {reply.requestId} failed: {err}", QuitFailure)
    of tdwrkResult:
      let timing = reply.result.timing
      totalWriteUs += timing.writeUs
      totalReadUs += timing.readUs
      totalParseUs += timing.parseUs
      totalSortUs += timing.sortUs
      lastDetectionCount = timing.detectionCount

      if reply.result.detections.len > 0:
        lastTop = reply.result.detections[0]
        hasTop = true

      if waitUs < minWaitUs:
        minWaitUs = waitUs
      if waitUs > maxWaitUs:
        maxWaitUs = waitUs

      inc completed

      if submitted < loops:
        quitIfErr(
          worker.submitCopy(inputTemplate, uint64(submitted), threshold),
          "submitCopy"
        )
        inc submitted

  let elapsedUs = inMicroseconds(getMonoTime() - started)
  let elapsedMs = float(elapsedUs) / 1000.0
  let fps =
    if elapsedUs > 0:
      float(loops) * 1_000_000.0 / float(elapsedUs)
    else:
      0.0

  echo ""
  echo "Threadtools detector worker summary:"
  echo &"  elapsed    : {elapsedMs:.3f} ms"
  echo &"  fps        : {fps:.2f}"
  echo &"  avg write  : {float(totalWriteUs) / float(loops) / 1000.0:.3f} ms"
  echo &"  avg read   : {float(totalReadUs) / float(loops) / 1000.0:.3f} ms"
  echo &"  avg parse  : {float(totalParseUs) / float(loops) / 1000.0:.3f} ms"
  echo &"  avg sort   : {float(totalSortUs) / float(loops) / 1000.0:.3f} ms"
  echo &"  wait min   : {float(minWaitUs) / 1000.0:.3f} ms"
  echo &"  wait max   : {float(maxWaitUs) / 1000.0:.3f} ms"
  echo &"  last det   : {lastDetectionCount}"

  if hasTop:
    echo ""
    echo "Top detection:"
    echo &"  class={lastTop.classId} score={lastTop.score:.4f} box=({lastTop.xMin:.4f}, {lastTop.yMin:.4f}, {lastTop.xMax:.4f}, {lastTop.yMax:.4f})"

# ------------------------------------------------------------------------------
# isMainModule
# ------------------------------------------------------------------------------

when isMainModule:
  main()
