import std/[monotimes, os, strformat, strutils, times]

import hailort_nim
import hailort_nim/highlevel/threadtools_detector

proc getOrQuit[T](r: HE[T]; label: string): T =
  if r.isErr:
    quit(&"{label} failed: {r.error}", QuitFailure)

  result = r.get

proc readFileBytes(path: string): seq[byte] =
  let s = readFile(path)
  result = newSeq[byte](s.len)

  if s.len > 0:
    copyMem(addr result[0], unsafeAddr s[0], s.len)

proc parseIntArg(index: int; defaultValue: int): int =
  if paramCount() >= index:
    parseInt(paramStr(index))
  else:
    defaultValue

proc parseFloatArg(index: int; defaultValue: float): float =
  if paramCount() >= index:
    parseFloat(paramStr(index))
  else:
    defaultValue

proc usage() =
  let prog = getAppFilename().extractFilename()
  echo &"Usage: {prog} <hef> <raw-input> [loops] [slots] [batch-size] [score-threshold]"
  echo ""
  echo "batch-size: 0 keeps HailoRT default/auto behavior."
  echo "For batching tests, use slots >= batch-size so several requests can be in flight."
  echo ""
  echo "Examples:"
  echo &"  {prog} yolov11s.hef dog.raw 100 4 0 0.25"
  echo &"  {prog} yolov11s.hef dog.raw 100 8 4 0.25"

proc printNetworkGroupInfos(hefPath: string) =
  let hef = getOrQuit(openHef(hefPath), "openHef")
  defer:
    discard hef.close()

  let infos = getOrQuit(hef.getNetworkGroupInfos(), "getNetworkGroupInfos")

  echo "HEF network groups:"
  if infos.len == 0:
    echo "  none"
    return

  for i, info in infos:
    echo &"  [{i}] name={info.name()} multi_context={info.is_multi_context}"

proc main() =
  if paramCount() < 2:
    usage()
    quit(QuitFailure)

  let hefPath = paramStr(1)
  let rawPath = paramStr(2)
  let loops = parseIntArg(3, 100)
  let slots = parseIntArg(4, 4)
  let requestedBatchSize = parseIntArg(5, int(HAILO_DEFAULT_BATCH_SIZE))
  let threshold = parseFloatArg(6, 0.25).float32

  if loops <= 0:
    quit("loops must be positive", QuitFailure)
  if slots <= 0:
    quit("slots must be positive", QuitFailure)
  if requestedBatchSize < 0 or requestedBatchSize > int(high(uint16)):
    quit("batch-size must be in uint16 range", QuitFailure)

  printNetworkGroupInfos(hefPath)

  let input = readFileBytes(rawPath)
  let det = getOrQuit(
    Detector.open(hefPath, batchSize = uint16(requestedBatchSize)),
    "Detector.open"
  )
  defer:
    discard det.close()

  if input.len != det.inputSize():
    quit(
      &"input size mismatch: expected={det.inputSize()} actual={input.len}",
      QuitFailure
    )

  let td = getOrQuit(det.openThreadtoolsDetector(slots), "openThreadtoolsDetector")
  defer:
    discard td.close()

  if requestedBatchSize > 1 and slots < requestedBatchSize:
    echo &"warning: slots={slots} is smaller than batch-size={requestedBatchSize}; batching may not fill efficiently"

  echo ""
  echo "Batch size probe:"
  echo &"  hef                  : {hefPath}"
  echo &"  raw                  : {rawPath}"
  echo &"  input_size           : {td.inputSize()}"
  echo &"  output_size          : {td.outputSize()}"
  echo &"  loops                : {loops}"
  echo &"  slots                : {td.slotCount()}"
  echo &"  requested_batch_size : {requestedBatchSize}"
  echo &"  detector_batch_size  : {det.configuredBatchSize()}"
  echo &"  threshold            : {threshold:.3f}"

  let initial = min(loops, td.slotCount())
  var submitted = 0
  var completed = 0
  var detections: seq[Detection] = @[]

  var totalWriteUs: int64 = 0
  var totalReadUs: int64 = 0
  var totalParseUs: int64 = 0
  var totalSortUs: int64 = 0
  var minWaitUs: int64 = high(int64)
  var maxWaitUs: int64 = 0
  var lastDetectionCount = 0

  let started = getMonoTime()

  for _ in 0 ..< initial:
    discard getOrQuit(td.submit(input), "submit")
    inc submitted

  while completed < loops:
    let waitStarted = getMonoTime()
    let r = getOrQuit(td.waitDetections(detections, threshold), "waitDetections")
    let waitUs = inMicroseconds(getMonoTime() - waitStarted)

    totalWriteUs += r.writeUs
    totalReadUs += r.readUs
    totalParseUs += r.parseUs
    totalSortUs += r.sortUs
    lastDetectionCount = r.detectionCount

    if waitUs < minWaitUs:
      minWaitUs = waitUs
    if waitUs > maxWaitUs:
      maxWaitUs = waitUs

    inc completed

    if submitted < loops:
      discard getOrQuit(td.submit(input), "submit")
      inc submitted

  let elapsedUs = inMicroseconds(getMonoTime() - started)
  let elapsedMs = float(elapsedUs) / 1000.0
  let fps =
    if elapsedUs > 0:
      float(loops) * 1_000_000.0 / float(elapsedUs)
    else:
      0.0

  echo ""
  echo "Summary:"
  echo &"  elapsed    : {elapsedMs:.3f} ms"
  echo &"  fps        : {fps:.2f}"
  echo &"  avg write  : {float(totalWriteUs) / float(loops) / 1000.0:.3f} ms"
  echo &"  avg read   : {float(totalReadUs) / float(loops) / 1000.0:.3f} ms"
  echo &"  avg parse  : {float(totalParseUs) / float(loops) / 1000.0:.3f} ms"
  echo &"  avg sort   : {float(totalSortUs) / float(loops) / 1000.0:.3f} ms"
  echo &"  wait min   : {float(minWaitUs) / 1000.0:.3f} ms"
  echo &"  wait max   : {float(maxWaitUs) / 1000.0:.3f} ms"
  echo &"  last det   : {lastDetectionCount}"

when isMainModule:
  main()
