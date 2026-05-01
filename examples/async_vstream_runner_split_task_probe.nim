when not compileOption("threads"):
  {.error: "async_vstream_runner_split_task_probe requires --threads:on".}

import std/[asyncdispatch, os, strformat, strutils, monotimes, times]

import hailort_nim
import hailort_nim/highlevel/async_vstream_runner
import hailort_nim/internal/mailbox

type
  ProbeStats = ref object
    submitted: int
    completed: int
    totalWriteUs: int64
    totalReadUs: int64
    minWaitUs: int64
    maxWaitUs: int64

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
# newProbeStats:
#
# ------------------------------------------------------------------------------

proc newProbeStats(): ProbeStats =
  result = ProbeStats(
    submitted: 0,
    completed: 0,
    totalWriteUs: 0,
    totalReadUs: 0,
    minWaitUs: high(int64),
    maxWaitUs: 0
  )

# ------------------------------------------------------------------------------
#
# writeTask:
#
# ------------------------------------------------------------------------------

proc writeTask(
  runner: AsyncVStreamRunner;
  input: seq[byte];
  loops: int;
  readFutures: Mailbox[AsyncVStreamReadFuture];
  stats: ProbeStats
) {.async.} =
  ## Write/submit side.
  ##
  ## This task waits for a free output slot, performs inputVstream.write()
  ## synchronously via writeAsync(), and sends the returned read Future to
  ## readTask.
  for i in 0 ..< loops:
    let ready = await runner.waitWritable()

    if ready.isErr:
      readFutures.close()
      quit(&"waitWritable failed: {ready.error}", QuitFailure)

    let readFutureRes = runner.writeAsync(input)

    if readFutureRes.isErr:
      readFutures.close()
      quit(&"writeAsync failed: {readFutureRes.error}", QuitFailure)

    inc stats.submitted
    readFutures.send(readFutureRes.get)

  readFutures.close()

# ------------------------------------------------------------------------------
#
# readTask:
#
# ------------------------------------------------------------------------------

proc readTask(
  runner: AsyncVStreamRunner;
  readFutures: Mailbox[AsyncVStreamReadFuture];
  stats: ProbeStats
) {.async.} =
  ## Read/result side.
  ##
  ## This task receives read Futures from writeTask and awaits them. A real app
  ## would parse result.outputPtr, draw, encode, or forward the slot here.
  while true:
    let readFuture =
      try:
        await readFutures.recv()
      except MailboxClosedError:
        break

    let waitStarted = getMonoTime()
    let res = await readFuture
    let waitUs = inMicroseconds(getMonoTime() - waitStarted)

    if res.isErr:
      quit(&"read result failed: {res.error}", QuitFailure)

    let r = res.get

    stats.totalWriteUs += r.writeUs
    stats.totalReadUs += r.readUs

    if waitUs < stats.minWaitUs:
      stats.minWaitUs = waitUs
    if waitUs > stats.maxWaitUs:
      stats.maxWaitUs = waitUs

    inc stats.completed

    # A real app may parse/use r.outputPtr before releasing.
    checkOrQuit(runner.releaseResult(r), "releaseResult")

# ------------------------------------------------------------------------------
#
# usage:
#
# ------------------------------------------------------------------------------

proc usage() =
  echo "Usage: async_vstream_runner_split_task_probe <hef> <raw-input> [loops] [slots]"
  echo ""
  echo "Example:"
  echo "  async_vstream_runner_split_task_probe yolov11n.hef dog_640x640x3.raw 100 2"
  echo ""
  echo "This probe splits write and read/result handling into separate async tasks."

# ------------------------------------------------------------------------------
#
# run:
#
# ------------------------------------------------------------------------------

proc run() {.async.} =
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

  let readFutures = newMailbox[AsyncVStreamReadFuture]()
  let stats = newProbeStats()

  let started = getMonoTime()

  let wt = writeTask(runner, input, loops, readFutures, stats)
  let rt = readTask(runner, readFutures, stats)

  asyncCheck wt
  asyncCheck rt

  await wt
  await rt

  let elapsedUs = inMicroseconds(getMonoTime() - started)
  let elapsedMs = float(elapsedUs) / 1000.0
  let fps =
    if elapsedUs > 0:
      float(stats.completed) * 1_000_000.0 / float(elapsedUs)
    else:
      0.0

  echo ""
  echo "Split-task async vstream runner summary:"
  echo &"  elapsed    : {elapsedMs:.3f} ms"
  echo &"  fps        : {fps:.2f}"
  echo &"  submitted  : {stats.submitted}"
  echo &"  completed  : {stats.completed}"
  echo &"  avg write  : {float(stats.totalWriteUs) / float(stats.completed) / 1000.0:.3f} ms"
  echo &"  avg read   : {float(stats.totalReadUs) / float(stats.completed) / 1000.0:.3f} ms"
  echo &"  wait min   : {float(stats.minWaitUs) / 1000.0:.3f} ms"
  echo &"  wait max   : {float(stats.maxWaitUs) / 1000.0:.3f} ms"

# ------------------------------------------------------------------------------
#
# isMainModule:
#
# ------------------------------------------------------------------------------

when isMainModule:
  waitFor run()
