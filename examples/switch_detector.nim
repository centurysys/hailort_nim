import std/[os, strformat, strutils, monotimes, times]

import hailort_nim
import hailort_nim/lowlevel
import hailort_nim/lowlevel/common/vstream_types

import ./common/common

type
  PreparedModel = object
    path: string
    detector: Detector
    outputBuf: seq[byte]
    detections: seq[Detection]
    inputMeta: VStreamMetadata
    outputMeta: VStreamMetadata
    inputFrameSize: int
    outputFrameSize: int

  ModelStat = object
    path: string
    prepareMs: float
    activateTotalMs: float
    detectTotalMs: float
    deactivateTotalMs: float
    totalMs: float
    count: int
    detectionsTotal: int

proc elapsedMs(started: MonoTime): float =
  result = (getMonoTime() - started).inNanoseconds.float / 1_000_000.0

proc parseBoolArg(s: string): bool =
  let v = s.toLowerAscii()
  result = v in ["1", "true", "yes", "y", "on"]

proc firstAddr[T](s: seq[T]): string =
  if s.len == 0:
    result = "nil"
  else:
    result = &"0x{cast[uint](unsafeAddr s[0]):016X}"

proc printUsage() =
  let prog = getAppFilename().extractFilename()
  echo &"Usage: {prog} <input.raw> <model1.hef> <model2.hef> [model3.hef ...] [--loops N] [--warmup N] [--threshold X] [--hailo-threshold X] [--print-metadata true|false]"
  echo ""
  echo "Example:"
  echo &"  {prog} dog.raw yolov11n.hef yolov10n.hef --loops 20 --warmup 5"

proc parseArgs(
  inputPath: var string;
  modelPaths: var seq[string];
  loops: var int;
  warmup: var int;
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

proc printMetadata(m: PreparedModel; modelIndex: int) =
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

proc printSummary(stats: seq[ModelStat]) =
  echo ""
  echo "== summary =="
  for i, st in stats:
    if st.count == 0:
      echo &"model[{i}] {st.path}"
      echo &"  prepare        : {st.prepareMs:8.3f} ms"
      echo "  runs           : 0"
      continue

    let avgActivate = st.activateTotalMs / st.count.float
    let avgDetect = st.detectTotalMs / st.count.float
    let avgDeactivate = st.deactivateTotalMs / st.count.float
    let avgTotal = st.totalMs / st.count.float
    let avgDetections = st.detectionsTotal.float / st.count.float

    echo &"model[{i}] {st.path}"
    echo &"  prepare        : {st.prepareMs:8.3f} ms"
    echo &"  runs           : {st.count}"
    echo &"  avg activate   : {avgActivate:8.3f} ms"
    echo &"  avg detect     : {avgDetect:8.3f} ms"
    echo &"  avg deactivate : {avgDeactivate:8.3f} ms"
    echo &"  avg total      : {avgTotal:8.3f} ms"
    echo &"  avg detections : {avgDetections:8.3f}"

when isMainModule:
  var inputPath = ""
  var modelPaths: seq[string] = @[]
  var loops = 20
  var warmup = 5
  var appScoreThreshold = 0.25'f32
  var hailoScoreThreshold = 0.20'f32
  var shouldPrintMetadata = true

  parseArgs(
    inputPath,
    modelPaths,
    loops,
    warmup,
    appScoreThreshold,
    hailoScoreThreshold,
    shouldPrintMetadata
  )

  let input = readFile(inputPath)
  if input.len == 0:
    fail(&"input file is empty: {inputPath}")

  echo "== prepared detector activation switch test =="
  echo &"Input raw       : {inputPath}"
  echo &"Input len       : {input.len}"
  echo &"Models          : {modelPaths.len}"
  echo &"Loops           : {loops}"
  echo &"Warmup          : {warmup}"
  echo &"App threshold   : {appScoreThreshold}"
  echo &"Hailo threshold : {hailoScoreThreshold}"
  echo ""

  echo "== opening shared runtime =="
  let runtimeStart = getMonoTime()
  let runtime = HailoRuntime.open().getOrFail("HailoRuntime.open")
  echo &"runtime open : {elapsedMs(runtimeStart):.3f} ms"
  echo &"runtime open?: {runtime.isOpen()}"
  echo ""

  var models: seq[PreparedModel] = @[]
  var stats: seq[ModelStat] = @[]

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

    var m = PreparedModel(
      path: path,
      detector: detector,
      outputBuf: newSeq[byte](outputFrameSize),
      detections: @[],
      inputMeta: inputMeta,
      outputMeta: outputMeta,
      inputFrameSize: inputFrameSize,
      outputFrameSize: outputFrameSize
    )
    models.add(m)

    stats.add(ModelStat(
      path: path,
      prepareMs: prepareMs
    ))

    echo &"model[{modelIndex}] {path} prepare={prepareMs:8.3f} ms activated={detector.isActivated()}"
    if shouldPrintMetadata:
      printMetadata(models[^1], modelIndex)

  proc runOne(modelIndex: int; phase: string; iteration: int) =
    let totalStart = getMonoTime()

    let activateStart = getMonoTime()
    models[modelIndex].detector.activate().checkOrFail(&"activate({models[modelIndex].path})")
    let activateMs = elapsedMs(activateStart)

    models[modelIndex].detections.setLen(0)

    let detectStart = getMonoTime()
    models[modelIndex].detector.detectNmsByClassAutoInto(
      input.toOpenArrayByte(0, input.len - 1),
      models[modelIndex].outputBuf,
      models[modelIndex].detections,
      appScoreThreshold
    ).checkOrFail(&"detectNmsByClassAutoInto({models[modelIndex].path})")
    let detectMs = elapsedMs(detectStart)

    let deactivateStart = getMonoTime()
    models[modelIndex].detector.deactivate().checkOrFail(&"deactivate({models[modelIndex].path})")
    let deactivateMs = elapsedMs(deactivateStart)

    let totalMs = elapsedMs(totalStart)

    if phase == "loop":
      stats[modelIndex].activateTotalMs += activateMs
      stats[modelIndex].detectTotalMs += detectMs
      stats[modelIndex].deactivateTotalMs += deactivateMs
      stats[modelIndex].totalMs += totalMs
      stats[modelIndex].count += 1
      stats[modelIndex].detectionsTotal += models[modelIndex].detections.len

    echo &"{phase}[{iteration:>2}] model[{modelIndex}] activate={activateMs:8.3f} ms detect={detectMs:8.3f} ms deactivate={deactivateMs:8.3f} ms total={totalMs:8.3f} ms detections={models[modelIndex].detections.len} output={firstAddr(models[modelIndex].outputBuf)} first_detection={firstAddr(models[modelIndex].detections)}"

  echo ""
  echo "== warmup =="
  for i in 0 ..< warmup:
    for modelIndex in 0 ..< models.len:
      runOne(modelIndex, "warmup", i)

  echo ""
  echo "== activation switching loop =="
  let loopStart = getMonoTime()
  for i in 0 ..< loops:
    let roundStart = getMonoTime()
    for modelIndex in 0 ..< models.len:
      runOne(modelIndex, "loop", i)
    echo &"round[{i:>2}] total={elapsedMs(roundStart):8.3f} ms"

  let loopMs = elapsedMs(loopStart)
  echo ""
  echo "== loop timing =="
  echo &"total      : {loopMs:.3f} ms"
  echo &"per round  : {loopMs / loops.float:.3f} ms"
  echo &"round fps  : {1000.0 / (loopMs / loops.float):.2f}"

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
