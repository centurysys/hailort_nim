when not compileOption("threads"):
  {.error: "async_detector_probe requires --threads:on".}

import std/[os, strformat, strutils, monotimes, times]

import hailort_nim
import hailort_nim/highlevel/async_detector

# ------------------------------------------------------------------------------
#
# getOrQuit:
#
# ------------------------------------------------------------------------------

proc getOrQuit[T](r: HE[T]; label: string): T =
  if r.isErr:
    quit(&"{label} failed: {r.error}", QuitFailure)

  result = r.get

# ------------------------------------------------------------------------------
#
# readFileBytes:
#
# ------------------------------------------------------------------------------

proc readFileBytes(path: string): seq[byte] =
  let s = readFile(path)
  result = newSeq[byte](s.len)

  if s.len > 0:
    copyMem(addr result[0], unsafeAddr s[0], s.len)

# ------------------------------------------------------------------------------
#
# usage:
#
# ------------------------------------------------------------------------------

proc usage() =
  echo "Usage: async_detector_probe <hef> <raw-input> [loops] [slots] [score-threshold]"
  echo ""
  echo "Example:"
  echo "  async_detector_probe yolov11n.hef dog_640x640x3.raw 100 2 0.25"

# ------------------------------------------------------------------------------
#
# main:
#
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
  let threshold =
    if paramCount() >= 5:
      parseFloat(paramStr(5)).float32
    else:
      0.25'f32

  let input = readFileBytes(rawPath)
  let det = getOrQuit(Detector.open(hefPath), "Detector.open")
  defer:
    discard det.close()

  if input.len != det.inputSize():
    quit(
      &"input size mismatch: expected={det.inputSize()} actual={input.len}",
      QuitFailure
    )

  let ad = getOrQuit(det.openAsyncDetector(slots), "openAsyncDetector")
  defer:
    discard ad.close()

  echo &"hef={hefPath}"
  echo &"raw={rawPath}"
  echo &"input_size={ad.inputSize()} output_size={ad.outputSize()}"
  echo &"loops={loops} slots={ad.slotCount()} threshold={threshold:.3f}"

  let initial = min(loops, ad.slotCount())
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

  for i in 0 ..< initial:
    discard getOrQuit(ad.submit(input), "submit")
    inc submitted

  while completed < loops:
    let waitStarted = getMonoTime()
    let r = getOrQuit(ad.waitDetections(detections, threshold), "waitDetections")
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
      discard getOrQuit(ad.submit(input), "submit")
      inc submitted

  let elapsedUs = inMicroseconds(getMonoTime() - started)
  let elapsedMs = float(elapsedUs) / 1000.0
  let fps =
    if elapsedUs > 0:
      float(loops) * 1_000_000.0 / float(elapsedUs)
    else:
      0.0

  echo ""
  echo "Async detector summary:"
  echo &"  elapsed    : {elapsedMs:.3f} ms"
  echo &"  fps        : {fps:.2f}"
  echo &"  avg write  : {float(totalWriteUs) / float(loops) / 1000.0:.3f} ms"
  echo &"  avg read   : {float(totalReadUs) / float(loops) / 1000.0:.3f} ms"
  echo &"  avg parse  : {float(totalParseUs) / float(loops) / 1000.0:.3f} ms"
  echo &"  avg sort   : {float(totalSortUs) / float(loops) / 1000.0:.3f} ms"
  echo &"  wait min   : {float(minWaitUs) / 1000.0:.3f} ms"
  echo &"  wait max   : {float(maxWaitUs) / 1000.0:.3f} ms"
  echo &"  last det   : {lastDetectionCount}"

  if detections.len > 0:
    let d = detections[0]
    echo ""
    echo "Top detection:"
    echo &"  class={d.classId} score={d.score:.4f} box=({d.xMin:.4f}, {d.yMin:.4f}, {d.xMax:.4f}, {d.yMax:.4f})"

# ------------------------------------------------------------------------------
#
# isMainModule:
#
# ------------------------------------------------------------------------------

when isMainModule:
  main()
