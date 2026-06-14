import std/[os, strformat, strutils, monotimes, times]

import hailort_nim
import hailort_nim/lowlevel
import hailort_nim/lowlevel/common/vstream_types
import hailort_nim/highlevel/threadtools_detector

# ==============================================================================
# Types
# ==============================================================================

type
  PreparedSwitchModel = object
    path: string
    detector: Detector
    detections: seq[Detection]
    inputMeta: VStreamMetadata
    outputMeta: VStreamMetadata
    inputFrameSize: int
    outputFrameSize: int

  SwitchModelStat = object
    path: string
    prepareMs: float
    activateTotalMs: float
    openRunnerTotalMs: float
    submitTotalMs: float
    waitTotalMs: float
    closeRunnerTotalMs: float
    deactivateTotalMs: float
    totalMs: float
    switchCount: int
    requestCount: int
    detectionsTotal: int
    writeUsTotal: int64
    readUsTotal: int64
    parseUsTotal: int64
    sortUsTotal: int64

# ==============================================================================
# Small helpers
# ==============================================================================

proc elapsedMs(started: MonoTime): float {.inline.} =
  result = (getMonoTime() - started).inNanoseconds.float / 1_000_000.0

proc parseBoolArg(s: string): bool =
  let v = s.toLowerAscii()
  result = v in ["1", "true", "yes", "y", "on"]

proc fail(msg: string) {.noreturn.} =
  stderr.writeLine(msg)
  quit(1)

proc getOrFail[T](r: HE[T]; label: string): T =
  if r.isErr:
    fail(&"{label} failed: {r.error}")

  result = r.get

proc checkOrFail(r: HE[void]; label: string) =
  if r.isErr:
    fail(&"{label} failed: {r.error}")

proc readFileBytes(path: string): seq[byte] =
  let s = readFile(path)
  result = newSeq[byte](s.len)

  if s.len > 0:
    copyMem(addr result[0], unsafeAddr s[0], s.len)

# ==============================================================================
# CLI
# ==============================================================================

proc printUsage() =
  let prog = getAppFilename().extractFilename()
  echo &"Usage: {prog} <input.raw> <model1.hef> <model2.hef> [model3.hef ...] [--loops N] [--warmup N] [--batch N] [--slots N] [--threshold X] [--hailo-threshold X] [--print-metadata true|false]"
  echo ""
  echo "This probe measures prepared Detector switching with the threadtools detector path."
  echo "Each model is activated, a ThreadtoolsDetector is opened, N requests are submitted,"
  echo "then the ThreadtoolsDetector is closed and the model is deactivated."
  echo ""
  echo "Examples:"
  echo &"  {prog} dog.raw yolov11s.hef yolov11n.hef --loops 20 --warmup 3 --batch 1 --slots 2"
  echo &"  {prog} dog.raw yolov11s.hef yolov11n.hef --loops 20 --warmup 3 --batch 4 --slots 2"

proc parseArgs(
  inputPath: var string;
  modelPaths: var seq[string];
  loops: var int;
  warmup: var int;
  batchSize: var int;
  slots: var int;
  appScoreThreshold: var float32;
  hailoScoreThreshold: var float32;
  shouldPrintMetadata: var bool
) =
  if paramCount() < 3:
    printUsage()
    quit(1)

  inputPath = paramStr(1)

  var i = 2
  while i <= paramCount():
    let a = paramStr(i)

    case a
    of "--loops":
      inc i
      if i > paramCount():
        fail("--loops requires a value")
      loops = parseInt(paramStr(i))
    of "--warmup":
      inc i
      if i > paramCount():
        fail("--warmup requires a value")
      warmup = parseInt(paramStr(i))
    of "--batch":
      inc i
      if i > paramCount():
        fail("--batch requires a value")
      batchSize = parseInt(paramStr(i))
    of "--slots":
      inc i
      if i > paramCount():
        fail("--slots requires a value")
      slots = parseInt(paramStr(i))
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
    of "--print-metadata":
      inc i
      if i > paramCount():
        fail("--print-metadata requires a value")
      shouldPrintMetadata = parseBoolArg(paramStr(i))
    else:
      if a.startsWith("-"):
        fail(&"unknown option: {a}")
      modelPaths.add(a)

    inc i

  if modelPaths.len == 0:
    fail("no model HEF paths were specified")
  if loops <= 0:
    fail("--loops must be positive")
  if warmup < 0:
    fail("--warmup must be >= 0")
  if batchSize <= 0:
    fail("--batch must be positive")
  if slots <= 0:
    fail("--slots must be positive")

# ==============================================================================
# Output helpers
# ==============================================================================

proc printMetadata(m: PreparedSwitchModel; modelIndex: int) =
  echo &"model[{modelIndex}] {m.path}"
  echo "  input:"
  echo &"    name       : {m.inputMeta.name}"
  echo &"    network    : {m.inputMeta.networkName}"
  echo &"    type       : {m.inputMeta.dataType}"
  echo &"    order      : {m.inputMeta.pixelFormat}"
  echo &"    image_type : {m.inputMeta.imageType}"
  echo &"    shape      : {m.inputMeta.shape}"
  echo &"    frame_size : {m.inputFrameSize}"
  echo "  output:"
  echo &"    name       : {m.outputMeta.name}"
  echo &"    network    : {m.outputMeta.networkName}"
  echo &"    type       : {m.outputMeta.dataType}"
  echo &"    order      : {m.outputMeta.pixelFormat}"
  echo &"    image_type : {m.outputMeta.imageType}"
  echo &"    shape      : {m.outputMeta.shape}"
  echo &"    frame_size : {m.outputFrameSize}"

proc avgMs(total: float; count: int): float =
  if count <= 0:
    result = 0.0
  else:
    result = total / count.float

proc avgStageMs(totalUs: int64; count: int): float =
  if count <= 0:
    result = 0.0
  else:
    result = totalUs.float / count.float / 1000.0

proc printSummary(stats: seq[SwitchModelStat]) =
  echo ""
  echo "== summary =="
  for i, st in stats:
    echo &"model[{i}] {st.path}"
    echo &"  prepare              : {st.prepareMs:8.3f} ms"

    if st.switchCount == 0:
      echo "  switches             : 0"
      continue

    echo &"  switches             : {st.switchCount}"
    echo &"  requests             : {st.requestCount}"
    echo &"  avg activate         : {avgMs(st.activateTotalMs, st.switchCount):8.3f} ms"
    echo &"  avg open runner      : {avgMs(st.openRunnerTotalMs, st.switchCount):8.3f} ms"
    echo &"  avg submit per req   : {avgMs(st.submitTotalMs, st.requestCount):8.3f} ms"
    echo &"  avg wait per req     : {avgMs(st.waitTotalMs, st.requestCount):8.3f} ms"
    echo &"  avg close runner     : {avgMs(st.closeRunnerTotalMs, st.switchCount):8.3f} ms"
    echo &"  avg deactivate       : {avgMs(st.deactivateTotalMs, st.switchCount):8.3f} ms"
    echo &"  avg total per switch : {avgMs(st.totalMs, st.switchCount):8.3f} ms"
    echo &"  avg write per req    : {avgStageMs(st.writeUsTotal, st.requestCount):8.3f} ms"
    echo &"  avg read per req     : {avgStageMs(st.readUsTotal, st.requestCount):8.3f} ms"
    echo &"  avg parse per req    : {avgStageMs(st.parseUsTotal, st.requestCount):8.3f} ms"
    echo &"  avg sort per req     : {avgStageMs(st.sortUsTotal, st.requestCount):8.3f} ms"
    echo &"  avg detections/req   : {st.detectionsTotal.float / st.requestCount.float:8.3f}"

# ==============================================================================
# Main
# ==============================================================================

when isMainModule:
  var inputPath = ""
  var modelPaths: seq[string] = @[]
  var loops = 20
  var warmup = 3
  var batchSize = 1
  var slots = 2
  var appScoreThreshold = 0.25'f32
  var hailoScoreThreshold = 0.20'f32
  var shouldPrintMetadata = true

  parseArgs(
    inputPath,
    modelPaths,
    loops,
    warmup,
    batchSize,
    slots,
    appScoreThreshold,
    hailoScoreThreshold,
    shouldPrintMetadata
  )

  let input = readFileBytes(inputPath)
  if input.len == 0:
    fail(&"input file is empty: {inputPath}")

  var runnerConfig = defaultThreadtoolsVStreamRunnerConfig()
  runnerConfig.slotCount = slots
  runnerConfig.inputQueueSize = slots
  runnerConfig.resultQueueSize = slots

  echo "== threadtools prepared detector switch probe =="
  echo &"Input raw       : {inputPath}"
  echo &"Input len       : {input.len}"
  echo &"Models          : {modelPaths.len}"
  echo &"Loops           : {loops}"
  echo &"Warmup          : {warmup}"
  echo &"Batch/model     : {batchSize}"
  echo &"Slots           : {slots}"
  echo &"App threshold   : {appScoreThreshold}"
  echo &"Hailo threshold : {hailoScoreThreshold}"
  echo ""

  echo "== opening shared runtime =="
  let runtimeStart = getMonoTime()
  let runtime = HailoRuntime.open().getOrFail("HailoRuntime.open")
  echo &"runtime open : {elapsedMs(runtimeStart):.3f} ms"
  echo &"runtime open?: {runtime.isOpen()}"
  echo ""

  var models: seq[PreparedSwitchModel] = @[]
  var stats: seq[SwitchModelStat] = @[]

  echo "== preparing models =="
  for modelIndex, path in modelPaths:
    let prepareStart = getMonoTime()
    let detector = Detector.openPrepared(
      runtime,
      path,
      hailoScoreThreshold
    ).getOrFail(&"Detector.openPrepared(shared runtime, {path})")
    let prepareMs = elapsedMs(prepareStart)

    let inputMeta = detector.inputMetadata.getOrFail("inputMetadata")
    let outputMeta = detector.outputMetadata.getOrFail("outputMetadata")
    let inputFrameSize = detector.inputFrameSize
    let outputFrameSize = detector.outputFrameSize

    if input.len != inputFrameSize:
      fail(&"input length mismatch for model[{modelIndex}] {path}: got {input.len}, expected {inputFrameSize}")

    models.add PreparedSwitchModel(
      path: path,
      detector: detector,
      detections: @[],
      inputMeta: inputMeta,
      outputMeta: outputMeta,
      inputFrameSize: inputFrameSize,
      outputFrameSize: outputFrameSize
    )

    stats.add SwitchModelStat(
      path: path,
      prepareMs: prepareMs
    )

    echo &"model[{modelIndex}] {path} prepare={prepareMs:8.3f} ms activated={detector.isActivated()}"
    if shouldPrintMetadata:
      printMetadata(models[^1], modelIndex)

  proc runActiveModel(modelIndex: int; phase: string; iteration: int) =
    let totalStart = getMonoTime()

    let activateStart = getMonoTime()
    models[modelIndex].detector.activate().checkOrFail(&"activate({models[modelIndex].path})")
    let activateMs = elapsedMs(activateStart)

    let openStart = getMonoTime()
    let td = models[modelIndex].detector.openThreadtoolsDetector(runnerConfig).getOrFail(
      &"openThreadtoolsDetector({models[modelIndex].path})"
    )
    let openRunnerMs = elapsedMs(openStart)

    if td.slotCount() <= 0:
      fail(&"threadtools detector slot count is invalid for model[{modelIndex}] {models[modelIndex].path}")

    var submitted = 0
    var completed = 0
    let initial = min(batchSize, td.slotCount())

    var submitMsTotal = 0.0
    var waitMsTotal = 0.0
    var writeUsTotal: int64 = 0
    var readUsTotal: int64 = 0
    var parseUsTotal: int64 = 0
    var sortUsTotal: int64 = 0
    var detectionsTotal = 0
    var lastDetectionCount = 0
    var lastTop: Detection
    var hasTop = false

    for _ in 0 ..< initial:
      let submitStart = getMonoTime()
      discard td.submit(input).getOrFail(&"submit({models[modelIndex].path})")
      submitMsTotal += elapsedMs(submitStart)
      inc submitted

    while completed < batchSize:
      let waitStart = getMonoTime()
      let detectTiming = td.waitDetections(
        models[modelIndex].detections,
        appScoreThreshold
      ).getOrFail(&"waitDetections({models[modelIndex].path})")
      waitMsTotal += elapsedMs(waitStart)

      writeUsTotal += detectTiming.writeUs
      readUsTotal += detectTiming.readUs
      parseUsTotal += detectTiming.parseUs
      sortUsTotal += detectTiming.sortUs
      lastDetectionCount = detectTiming.detectionCount
      detectionsTotal += detectTiming.detectionCount

      if models[modelIndex].detections.len > 0:
        lastTop = models[modelIndex].detections[0]
        hasTop = true

      inc completed

      if submitted < batchSize:
        let submitStart = getMonoTime()
        discard td.submit(input).getOrFail(&"submit({models[modelIndex].path})")
        submitMsTotal += elapsedMs(submitStart)
        inc submitted

    let closeStart = getMonoTime()
    td.close().checkOrFail(&"ThreadtoolsDetector.close({models[modelIndex].path})")
    let closeRunnerMs = elapsedMs(closeStart)

    let deactivateStart = getMonoTime()
    models[modelIndex].detector.deactivate().checkOrFail(&"deactivate({models[modelIndex].path})")
    let deactivateMs = elapsedMs(deactivateStart)

    let totalMs = elapsedMs(totalStart)

    if phase == "loop":
      stats[modelIndex].activateTotalMs += activateMs
      stats[modelIndex].openRunnerTotalMs += openRunnerMs
      stats[modelIndex].submitTotalMs += submitMsTotal
      stats[modelIndex].waitTotalMs += waitMsTotal
      stats[modelIndex].closeRunnerTotalMs += closeRunnerMs
      stats[modelIndex].deactivateTotalMs += deactivateMs
      stats[modelIndex].totalMs += totalMs
      stats[modelIndex].switchCount += 1
      stats[modelIndex].requestCount += batchSize
      stats[modelIndex].detectionsTotal += detectionsTotal
      stats[modelIndex].writeUsTotal += writeUsTotal
      stats[modelIndex].readUsTotal += readUsTotal
      stats[modelIndex].parseUsTotal += parseUsTotal
      stats[modelIndex].sortUsTotal += sortUsTotal

    echo &"{phase}[{iteration:>2}] model[{modelIndex}] batch={batchSize} activate={activateMs:8.3f} ms open={openRunnerMs:8.3f} ms submit={submitMsTotal:8.3f} ms wait={waitMsTotal:8.3f} ms close={closeRunnerMs:8.3f} ms deactivate={deactivateMs:8.3f} ms total={totalMs:8.3f} ms last_det={lastDetectionCount}"
    if hasTop:
      echo &"  top class={lastTop.classId} score={lastTop.score:.4f} box=({lastTop.xMin:.4f}, {lastTop.yMin:.4f}, {lastTop.xMax:.4f}, {lastTop.yMax:.4f})"

  echo ""
  echo "== warmup =="
  for i in 0 ..< warmup:
    for modelIndex in 0 ..< models.len:
      runActiveModel(modelIndex, "warmup", i)

  echo ""
  echo "== switch loop =="
  let loopStart = getMonoTime()
  for i in 0 ..< loops:
    let roundStart = getMonoTime()
    for modelIndex in 0 ..< models.len:
      runActiveModel(modelIndex, "loop", i)
    echo &"round[{i:>2}] total={elapsedMs(roundStart):8.3f} ms"

  let loopMs = elapsedMs(loopStart)
  let totalRequests = loops * models.len * batchSize
  echo ""
  echo "== loop timing =="
  echo &"total        : {loopMs:.3f} ms"
  echo &"per round    : {loopMs / loops.float:.3f} ms"
  echo &"round fps    : {1000.0 / (loopMs / loops.float):.2f}"
  echo &"requests     : {totalRequests}"
  echo &"request fps  : {totalRequests.float * 1000.0 / loopMs:.2f}"

  printSummary(stats)

  echo ""
  echo "== closing models =="
  for i in countdown(models.len - 1, 0):
    echo &"close model[{i}] {models[i].path}"
    models[i].detector.close().checkOrFail(&"Detector.close({models[i].path})")

  echo ""
  echo "== closing shared runtime =="
  runtime.close().checkOrFail("HailoRuntime.close")
  echo "done"
