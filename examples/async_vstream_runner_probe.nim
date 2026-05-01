import std/[os, strformat, strutils, monotimes, times]

import hailort_nim
import hailort_nim/highlevel/async_vstream_runner

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
# checkOrQuit:
#
# ------------------------------------------------------------------------------

proc checkOrQuit(r: HE[void]; label: string) =
  if r.isErr:
    quit(&"{label} failed: {r.error}", QuitFailure)

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
  echo "Usage: async_vstream_runner_probe <hef> <raw-input> [loops] [slots]"
  echo ""
  echo "Example:"
  echo "  async_vstream_runner_probe yolov11n.hef dog_640x640x3.raw 100 2"

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

  let input = readFileBytes(rawPath)
  let det = getOrQuit(Detector.open(hefPath), "Detector.open")
  defer:
    discard det.close()

  if input.len != det.inputSize():
    quit(
      &"input size mismatch: expected={det.inputSize()} actual={input.len}",
      QuitFailure
    )

  let runner = getOrQuit(det.openAsyncVStreamRunner(slots), "openAsyncVStreamRunner")
  defer:
    discard runner.close()

  echo &"hef={hefPath}"
  echo &"raw={rawPath}"
  echo &"input_size={runner.inputSize()} output_size={runner.outputSize()}"
  echo &"loops={loops} slots={runner.slotCount()}"

  let initial = min(loops, runner.slotCount())
  var submitted = 0
  var completed = 0
  var totalWriteUs: int64 = 0
  var totalReadUs: int64 = 0
  var minWaitUs: int64 = high(int64)
  var maxWaitUs: int64 = 0

  let started = getMonoTime()

  for i in 0 ..< initial:
    discard getOrQuit(runner.submit(input), "submit")
    inc submitted

  while completed < loops:
    let waitStarted = getMonoTime()
    let r = getOrQuit(runner.waitResult(), "waitResult")
    let waitUs = inMicroseconds(getMonoTime() - waitStarted)

    totalWriteUs += r.writeUs
    totalReadUs += r.readUs

    if waitUs < minWaitUs:
      minWaitUs = waitUs
    if waitUs > maxWaitUs:
      maxWaitUs = waitUs

    inc completed

    checkOrQuit(runner.releaseResult(r), "releaseResult")

    if submitted < loops:
      discard getOrQuit(runner.submit(input), "submit")
      inc submitted

  let elapsedUs = inMicroseconds(getMonoTime() - started)
  let elapsedMs = float(elapsedUs) / 1000.0
  let fps =
    if elapsedUs > 0:
      float(loops) * 1_000_000.0 / float(elapsedUs)
    else:
      0.0

  echo ""
  echo "Async vstream runner summary:"
  echo &"  elapsed    : {elapsedMs:.3f} ms"
  echo &"  fps        : {fps:.2f}"
  echo &"  avg write  : {float(totalWriteUs) / float(loops) / 1000.0:.3f} ms"
  echo &"  avg read   : {float(totalReadUs) / float(loops) / 1000.0:.3f} ms"
  echo &"  wait min   : {float(minWaitUs) / 1000.0:.3f} ms"
  echo &"  wait max   : {float(maxWaitUs) / 1000.0:.3f} ms"

# ------------------------------------------------------------------------------
#
# isMainModule:
#
# ------------------------------------------------------------------------------

when isMainModule:
  main()
