import std/[os, strformat, strutils, times, monotimes]

import hailort_nim
import hailort_nim/lowlevel

import ./common/common

type
  PreparedSlot = object
    detector: Detector
    outputBuf: seq[byte]
    detections: seq[Detection]

  TrialResult = object
    count: int
    prepareOk: bool
    inferOk: bool
    prepareMs: float
    switchMs: float
    errorMessage: string

proc elapsedMs(started: MonoTime): float =
  result = (getMonoTime() - started).inNanoseconds.float / 1_000_000.0

proc printUsage() =
  let prog = getAppFilename().extractFilename()
  echo &"Usage: {prog} <input.raw> <model.hef> [--max N] [--threshold X] [--hailo-threshold X]"
  echo ""
  echo "Example:"
  echo &"  {prog} dog.raw yolov11n.hef --max 12"

proc parseArgs(
  inputPath: var string;
  hefPath: var string;
  maxCount: var int;
  appScoreThreshold: var float32;
  hailoScoreThreshold: var float32
) =
  if paramCount() < 2:
    printUsage()
    quit(1)

  inputPath = paramStr(1)
  hefPath = paramStr(2)

  var i = 3
  while i <= paramCount():
    let a = paramStr(i)

    case a
    of "--max":
      inc i
      if i > paramCount():
        fail("--max requires a value")
      maxCount = parseInt(paramStr(i))
    of "--threshold":
      inc i
      if i > paramCount():
        fail("--threshold requires a value")
      appScoreThreshold = parseFloat(paramStr(i)).float32
    of "--hailo-threshold":
      inc i
      if i > paramCount():
        fail("--hailo-threshold requires a value")
      hailoScoreThreshold = parseFloat(paramStr(i)).float32
    else:
      fail(&"unknown option: {a}")

    inc i

proc closePrepared(slots: var seq[PreparedSlot]) =
  for i in countdown(slots.len - 1, 0):
    if not slots[i].detector.isNil:
      discard slots[i].detector.close()
      slots[i].detector = nil
  slots.setLen(0)

proc runTrial(
  input: string;
  hefPath: string;
  count: int;
  appScoreThreshold: float32;
  hailoScoreThreshold: float32
): TrialResult =
  result.count = count

  var runtime: HailoRuntime = nil
  var slots: seq[PreparedSlot] = @[]

  let totalPrepareStart = getMonoTime()

  let runtimeRes = HailoRuntime.open()
  if runtimeRes.isErr:
    result.prepareOk = false
    result.inferOk = false
    result.errorMessage = &"HailoRuntime.open failed: {runtimeRes.error}"
    return

  runtime = runtimeRes.get

  for i in 0 ..< count:
    let openRes = Detector.openPrepared(runtime, hefPath, hailoScoreThreshold)
    if openRes.isErr:
      result.prepareOk = false
      result.inferOk = false
      result.prepareMs = elapsedMs(totalPrepareStart)
      result.errorMessage = &"openPrepared[{i}] failed: {openRes.error}"
      closePrepared(slots)
      discard runtime.close()
      return

    let detector = openRes.get
    let inputFrameSize = detector.inputFrameSize
    let outputFrameSize = detector.outputFrameSize

    if input.len != inputFrameSize:
      result.prepareOk = false
      result.inferOk = false
      result.prepareMs = elapsedMs(totalPrepareStart)
      result.errorMessage = &"input length mismatch: got {input.len}, expected {inputFrameSize}"
      discard detector.close()
      closePrepared(slots)
      discard runtime.close()
      return

    slots.add(PreparedSlot(
      detector: detector,
      outputBuf: newSeq[byte](outputFrameSize),
      detections: @[]
    ))

  result.prepareOk = true
  result.prepareMs = elapsedMs(totalPrepareStart)

  let switchStart = getMonoTime()

  for i in 0 ..< slots.len:
    let actRes = slots[i].detector.activate()
    if actRes.isErr:
      result.inferOk = false
      result.switchMs = elapsedMs(switchStart)
      result.errorMessage = &"activate[{i}] failed: {actRes.error}"
      closePrepared(slots)
      discard runtime.close()
      return

    let detRes = slots[i].detector.detectNmsByClassAutoInto(
      input.toOpenArrayByte(0, input.len - 1),
      slots[i].outputBuf,
      slots[i].detections,
      appScoreThreshold
    )
    if detRes.isErr:
      discard slots[i].detector.deactivate()
      result.inferOk = false
      result.switchMs = elapsedMs(switchStart)
      result.errorMessage = &"detect[{i}] failed: {detRes.error}"
      closePrepared(slots)
      discard runtime.close()
      return

    let deactRes = slots[i].detector.deactivate()
    if deactRes.isErr:
      result.inferOk = false
      result.switchMs = elapsedMs(switchStart)
      result.errorMessage = &"deactivate[{i}] failed: {deactRes.error}"
      closePrepared(slots)
      discard runtime.close()
      return

  result.inferOk = true
  result.switchMs = elapsedMs(switchStart)

  closePrepared(slots)

  let closeRuntimeRes = runtime.close()
  if closeRuntimeRes.isErr:
    result.errorMessage = &"runtime.close failed: {closeRuntimeRes.error}"
    result.inferOk = false
    return

proc printTrial(r: TrialResult) =
  if r.prepareOk and r.inferOk:
    echo &"N={r.count:>2}: OK    prepare={r.prepareMs:8.3f} ms switch+infer={r.switchMs:8.3f} ms per_model={(r.switchMs / r.count.float):8.3f} ms"
  else:
    echo &"N={r.count:>2}: FAIL  prepare={r.prepareMs:8.3f} ms switch+infer={r.switchMs:8.3f} ms"
    echo &"      error: {r.errorMessage}"

when isMainModule:
  var inputPath = ""
  var hefPath = ""
  var maxCount = 12
  var appScoreThreshold = 0.25'f32
  var hailoScoreThreshold = 0.20'f32

  parseArgs(
    inputPath,
    hefPath,
    maxCount,
    appScoreThreshold,
    hailoScoreThreshold
  )

  let input = readFile(inputPath)
  if input.len == 0:
    fail(&"input file is empty: {inputPath}")

  echo "== prepared detector capacity test =="
  echo &"Input raw       : {inputPath}"
  echo &"Input len       : {input.len}"
  echo &"HEF             : {hefPath}"
  echo &"Max count       : {maxCount}"
  echo &"App threshold   : {appScoreThreshold}"
  echo &"Hailo threshold : {hailoScoreThreshold}"
  echo ""
  echo "This test recreates HailoRuntime for each N."
  echo "For each N: openPrepared N detectors, activate/detect/deactivate each, then close all."
  echo ""

  var maxOk = 0
  var firstFail: TrialResult
  var sawFail = false

  for n in 1 .. maxCount:
    let r = runTrial(
      input,
      hefPath,
      n,
      appScoreThreshold,
      hailoScoreThreshold
    )
    printTrial(r)

    if r.prepareOk and r.inferOk:
      maxOk = n
    else:
      firstFail = r
      sawFail = true
      break

  echo ""
  echo "== result =="
  echo &"max prepared detectors with successful inference: {maxOk}"

  if sawFail:
    echo &"first failure at N={firstFail.count}"
    echo &"failure reason: {firstFail.errorMessage}"
  else:
    echo "no failure within requested max count"
