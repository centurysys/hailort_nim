import std/[algorithm, monotimes, strformat, times]

import ../lowlevel
import ../models/detection

type
  DetectorProfile* = object
    inferCount*: int
    validateUs*: int64
    writeUs*: int64
    readUs*: int64
    parseUs*: int64
    sortUs*: int64

  Detector* = ref object
    ## High-level object-detection helper.
    ##
    ## Prepared detectors own HEF/network/vstreams. Activation is separated so
    ## multiple prepared detectors can share one HailoRuntime and be activated
    ## one at a time.
    runtime*: HailoRuntime
    ownsRuntime*: bool
    hef*: Hef
    vdevice*: Vdevice
    networkGroup*: NetworkGroup
    activated*: ActivatedNetworkGroup
    inputVstreams*: InputVStreams
    outputVstreams*: OutputVStreams
    inputVstream*: InputVStream
    outputVstream*: OutputVStream
    inputInfo*: VstreamInfo
    outputInfo*: VstreamInfo
    inputFrameSize*: int
    outputFrameSize*: int
    profiling*: bool
    profile*: DetectorProfile

# ------------------------------------------------------------------------------
# Profiling helpers:
# ------------------------------------------------------------------------------

proc addElapsedUs(dst: var int64; started: MonoTime) {.inline.} =
  dst += inMicroseconds(getMonoTime() - started)

# ------------------------------------------------------------------------------
#
# measureProfile:
#
# ------------------------------------------------------------------------------
template measureProfile(enabled: bool; dst: var int64; body: untyped): untyped =
  if enabled:
    let t0 = getMonoTime()
    body
    dst.addElapsedUs(t0)
  else:
    body

# ------------------------------------------------------------------------------
#
# resetProfile:
#
# ------------------------------------------------------------------------------
proc resetProfile*(d: Detector) =
  if d.isNil:
    return

  d.profile = DetectorProfile()

# ------------------------------------------------------------------------------
#
# enableProfiling:
#
# ------------------------------------------------------------------------------
proc enableProfiling*(d: Detector; enabled = true; reset = true) =
  if d.isNil:
    return

  d.profiling = enabled
  if reset:
    d.resetProfile()

# ------------------------------------------------------------------------------
#
# disableProfiling:
#
# ------------------------------------------------------------------------------
proc disableProfiling*(d: Detector; reset = false) =
  if d.isNil:
    return

  d.profiling = false
  if reset:
    d.resetProfile()

# ------------------------------------------------------------------------------
#
# avgMs:
#
# ------------------------------------------------------------------------------
proc avgMs(totalUs: int64; count: int): float =
  if count <= 0:
    result = 0.0
  else:
    result = float(totalUs) / float(count) / 1000.0

# ------------------------------------------------------------------------------
#
# profileSummary:
#
# ------------------------------------------------------------------------------
proc profileSummary*(d: Detector): string =
  if d.isNil:
    return "hailort_profile detector=nil"

  let p = d.profile
  let totalUs = p.validateUs + p.writeUs + p.readUs + p.parseUs + p.sortUs

  result =
    &"hailort_profile count={p.inferCount} " &
    &"avg_ms total={avgMs(totalUs, p.inferCount):.3f} " &
    &"validate={avgMs(p.validateUs, p.inferCount):.3f} " &
    &"write={avgMs(p.writeUs, p.inferCount):.3f} " &
    &"read={avgMs(p.readUs, p.inferCount):.3f} " &
    &"parse={avgMs(p.parseUs, p.inferCount):.3f} " &
    &"sort={avgMs(p.sortUs, p.inferCount):.3f}"

# ------------------------------------------------------------------------------
# NMS parsing:
# ------------------------------------------------------------------------------

proc readF32Le(data: openArray[byte]; offset: int): float32 =
  if offset + 4 > data.len:
    raise newException(ValueError, "readF32Le: offset out of range")

  copyMem(addr result, unsafeAddr data[offset], 4)

# ------------------------------------------------------------------------------
#
# parseNmsByClassVariableInto:
#
# ------------------------------------------------------------------------------
proc parseNmsByClassVariableInto*(
  raw: openArray[byte],
  numberOfClasses: int,
  maxBboxesPerClass: int,
  detections: var seq[Detection],
  appScoreThreshold = 0.25'f32
) =
  ## Parse HAILO_FORMAT_ORDER_HAILO_NMS_BY_CLASS variable-length layout into
  ## a caller-provided detection sequence.
  ##
  ## The sequence is cleared but its capacity is kept, allowing callers to reuse
  ## the same storage across streaming inference loops.
  detections.setLen(0)

  var offset = 0
  let rawLen = raw.len

  for classId in 0 ..< numberOfClasses:
    if offset + 4 > rawLen:
      return

    let countF = readF32Le(raw, offset)
    offset += 4

    var count = int(countF)
    if count < 0:
      count = 0
    if count > maxBboxesPerClass:
      count = maxBboxesPerClass

    for _ in 0 ..< count:
      if offset + 20 > rawLen:
        return

      let yMin = readF32Le(raw, offset + 0)
      let xMin = readF32Le(raw, offset + 4)
      let yMax = readF32Le(raw, offset + 8)
      let xMax = readF32Le(raw, offset + 12)
      let score = readF32Le(raw, offset + 16)
      offset += 20

      if appScoreThreshold <= 0 or score >= appScoreThreshold:
        detections.add(Detection(
          classId: classId,
          score: score,
          yMin: yMin,
          xMin: xMin,
          yMax: yMax,
          xMax: xMax
        ))

# ------------------------------------------------------------------------------
#
# parseNmsByClassVariable:
#
# ------------------------------------------------------------------------------
proc parseNmsByClassVariable*(
  raw: openArray[byte],
  numberOfClasses: int,
  maxBboxesPerClass: int,
  appScoreThreshold = 0.25'f32
): seq[Detection] =
  ## Allocation-returning compatibility wrapper.
  parseNmsByClassVariableInto(
    raw,
    numberOfClasses,
    maxBboxesPerClass,
    result,
    appScoreThreshold
  )

# ------------------------------------------------------------------------------
#
# sortByScoreDesc:
#
# ------------------------------------------------------------------------------
proc sortByScoreDesc*(detections: var seq[Detection]) =
  detections.sort(proc(a, b: Detection): int = cmp(b.score, a.score))

# ------------------------------------------------------------------------------
# Basic metadata:
# ------------------------------------------------------------------------------

proc inputSize*(d: Detector): int {.inline.} =
  result = d.inputFrameSize

# ------------------------------------------------------------------------------
#
# outputSize:
#
# ------------------------------------------------------------------------------
proc outputSize*(d: Detector): int {.inline.} =
  result = d.outputFrameSize

# ------------------------------------------------------------------------------
#
# isActivated:
#
# ------------------------------------------------------------------------------
proc isActivated*(d: Detector): bool {.inline.} =
  result = (not d.isNil) and (not d.activated.isNil)

# ------------------------------------------------------------------------------
#
# inputMetadata:
#
# ------------------------------------------------------------------------------
proc inputMetadata*(d: Detector): HE[VStreamMetadata] =
  if d.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "detector is nil").err

  result = d.inputInfo.metadata().ok

# ------------------------------------------------------------------------------
#
# outputMetadata:
#
# ------------------------------------------------------------------------------
proc outputMetadata*(d: Detector): HE[VStreamMetadata] =
  if d.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "detector is nil").err

  result = d.outputInfo.metadata().ok

# ------------------------------------------------------------------------------
#
# inputShape:
#
# ------------------------------------------------------------------------------
proc inputShape*(d: Detector): HE[ImageShape] =
  let mdRes = d.inputMetadata()
  if mdRes.isErr:
    return mdRes.error.err

  result = mdRes.get.shape.ok

# ------------------------------------------------------------------------------
#
# outputShape:
#
# ------------------------------------------------------------------------------
proc outputShape*(d: Detector): HE[ImageShape] =
  let mdRes = d.outputMetadata()
  if mdRes.isErr:
    return mdRes.error.err

  result = mdRes.get.shape.ok

# ------------------------------------------------------------------------------
#
# inputPixelFormat:
#
# ------------------------------------------------------------------------------
proc inputPixelFormat*(d: Detector): HE[PixelFormat] =
  let mdRes = d.inputMetadata()
  if mdRes.isErr:
    return mdRes.error.err

  result = mdRes.get.pixelFormat.ok

# ------------------------------------------------------------------------------
#
# outputPixelFormat:
#
# ------------------------------------------------------------------------------
proc outputPixelFormat*(d: Detector): HE[PixelFormat] =
  let mdRes = d.outputMetadata()
  if mdRes.isErr:
    return mdRes.error.err

  result = mdRes.get.pixelFormat.ok

# ------------------------------------------------------------------------------
#
# inputImageType:
#
# ------------------------------------------------------------------------------
proc inputImageType*(d: Detector): HE[ImageType] =
  let mdRes = d.inputMetadata()
  if mdRes.isErr:
    return mdRes.error.err

  result = mdRes.get.imageType.ok

# ------------------------------------------------------------------------------
#
# outputImageType:
#
# ------------------------------------------------------------------------------
proc outputImageType*(d: Detector): HE[ImageType] =
  let mdRes = d.outputMetadata()
  if mdRes.isErr:
    return mdRes.error.err

  result = mdRes.get.imageType.ok

# ------------------------------------------------------------------------------
# Activation lifecycle:
# ------------------------------------------------------------------------------

proc activate*(d: Detector): HE[void] =
  ## Activate this detector's network group.
  ##
  ## A Hailo device can have only one active network group at a time in this
  ## usage pattern. Call deactivate() before activating another prepared
  ## detector on the same runtime.
  if d.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "detector is nil").err
  if d.networkGroup.isNil:
    return makeError(HAILO_INVALID_OPERATION, "network group is nil").err
  if not d.activated.isNil:
    return okVoid()

  let activatedRes = d.networkGroup.activate()
  if activatedRes.isErr:
    return activatedRes.error.err

  d.activated = activatedRes.get
  result = okVoid()

# ------------------------------------------------------------------------------
#
# deactivate:
#
# ------------------------------------------------------------------------------
proc deactivate*(d: Detector): HE[void] =
  ## Deactivate this detector's network group, keeping HEF/network/vstreams alive.
  if d.isNil:
    return okVoid()
  if d.activated.isNil:
    return okVoid()

  let res = d.activated.close()
  if res.isErr:
    return res

  d.activated = nil
  result = okVoid()

# ------------------------------------------------------------------------------
# Close:
# ------------------------------------------------------------------------------

proc close*(d: Detector): HE[void] =
  if d.isNil:
    return okVoid()

  let deactRes = d.deactivate()
  if deactRes.isErr:
    return deactRes

  if not d.inputVstreams.isNil:
    let res = d.inputVstreams.close()
    if res.isErr:
      return res

  if not d.outputVstreams.isNil:
    let res = d.outputVstreams.close()
    if res.isErr:
      return res

  if not d.networkGroup.isNil:
    let res = d.networkGroup.close()
    if res.isErr:
      return res

  if not d.hef.isNil:
    let res = d.hef.close()
    if res.isErr:
      return res

  if d.ownsRuntime and not d.runtime.isNil:
    let res = d.runtime.close()
    if res.isErr:
      return res
  elif d.runtime.isNil and not d.vdevice.isNil:
    ## Compatibility fallback for older construction paths.
    let res = d.vdevice.close()
    if res.isErr:
      return res

  d.activated = nil
  d.inputVstreams = nil
  d.outputVstreams = nil
  d.inputVstream = nil
  d.outputVstream = nil
  d.networkGroup = nil
  d.vdevice = nil
  d.hef = nil
  d.runtime = nil
  d.ownsRuntime = false

  result = okVoid()

# ------------------------------------------------------------------------------
# Prepared open helpers:
# ------------------------------------------------------------------------------

proc openPreparedWithRuntime(
  runtime: HailoRuntime,
  hefPath: string,
  hailoNmsScoreThreshold: float32,
  ownsRuntime: bool,
  profiling = false
): HE[Detector] =
  if runtime.isNil or not runtime.isOpen():
    return makeError(HAILO_INVALID_ARGUMENT, "runtime is not open").err

  let hefRes = openHef(hefPath)
  if hefRes.isErr:
    if ownsRuntime:
      discard runtime.close()
    return hefRes.error.err

  let hefObj = hefRes.get
  let vdevObj = runtime.rawVdevice()

  if vdevObj.isNil or vdevObj.rawHandle.isNil:
    discard hefObj.close()
    if ownsRuntime:
      discard runtime.close()
    return makeError(HAILO_INVALID_ARGUMENT, "runtime vdevice is nil").err

  let ngRes = configureOne(vdevObj, hefObj)
  if ngRes.isErr:
    discard hefObj.close()
    if ownsRuntime:
      discard runtime.close()
    return ngRes.error.err

  let ngObj = ngRes.get

  let inputParamsRes = makeInputVstreamParams(ngObj)
  if inputParamsRes.isErr:
    discard ngObj.close()
    discard hefObj.close()
    if ownsRuntime:
      discard runtime.close()
    return inputParamsRes.error.err

  let inputParams = inputParamsRes.get

  let outputParamsRes = makeOutputVstreamParams(ngObj)
  if outputParamsRes.isErr:
    discard ngObj.close()
    discard hefObj.close()
    if ownsRuntime:
      discard runtime.close()
    return outputParamsRes.error.err

  let outputParams = outputParamsRes.get

  if inputParams.len != 1:
    discard ngObj.close()
    discard hefObj.close()
    if ownsRuntime:
      discard runtime.close()
    return makeError(
      HAILO_INVALID_OPERATION,
      &"Detector currently expects exactly 1 input vstream, got {inputParams.len}"
    ).err

  if outputParams.len != 1:
    discard ngObj.close()
    discard hefObj.close()
    if ownsRuntime:
      discard runtime.close()
    return makeError(
      HAILO_INVALID_OPERATION,
      &"Detector currently expects exactly 1 output vstream, got {outputParams.len}"
    ).err

  let inputVstreamsRes = createInputVstreams(ngObj, inputParams)
  if inputVstreamsRes.isErr:
    discard ngObj.close()
    discard hefObj.close()
    if ownsRuntime:
      discard runtime.close()
    return inputVstreamsRes.error.err

  let inputVstreams = inputVstreamsRes.get

  let outputVstreamsRes = createOutputVstreams(ngObj, outputParams)
  if outputVstreamsRes.isErr:
    discard inputVstreams.close()
    discard ngObj.close()
    discard hefObj.close()
    if ownsRuntime:
      discard runtime.close()
    return outputVstreamsRes.error.err

  let outputVstreams = outputVstreamsRes.get
  let inputVstream = inputVstreams[0]
  let outputVstream = outputVstreams[0]

  let inputInfoRes = inputVstream.info()
  if inputInfoRes.isErr:
    discard outputVstreams.close()
    discard inputVstreams.close()
    discard ngObj.close()
    discard hefObj.close()
    if ownsRuntime:
      discard runtime.close()
    return inputInfoRes.error.err

  let inputInfo = inputInfoRes.get

  let outputInfoRes = outputVstream.info()
  if outputInfoRes.isErr:
    discard outputVstreams.close()
    discard inputVstreams.close()
    discard ngObj.close()
    discard hefObj.close()
    if ownsRuntime:
      discard runtime.close()
    return outputInfoRes.error.err

  let outputInfo = outputInfoRes.get

  let inputFrameSizeRes = inputVstream.frameSize()
  if inputFrameSizeRes.isErr:
    discard outputVstreams.close()
    discard inputVstreams.close()
    discard ngObj.close()
    discard hefObj.close()
    if ownsRuntime:
      discard runtime.close()
    return inputFrameSizeRes.error.err

  let inputFrameSize = inputFrameSizeRes.get

  let outputFrameSizeRes = outputVstream.frameSize()
  if outputFrameSizeRes.isErr:
    discard outputVstreams.close()
    discard inputVstreams.close()
    discard ngObj.close()
    discard hefObj.close()
    if ownsRuntime:
      discard runtime.close()
    return outputFrameSizeRes.error.err

  let outputFrameSize = outputFrameSizeRes.get

  if hailoNmsScoreThreshold >= 0:
    let setThRes = outputVstream.setNmsScoreThreshold(hailoNmsScoreThreshold)
    if setThRes.isErr:
      discard outputVstreams.close()
      discard inputVstreams.close()
      discard ngObj.close()
      discard hefObj.close()
      if ownsRuntime:
        discard runtime.close()
      return setThRes.error.err

  result = Detector(
    runtime: runtime,
    ownsRuntime: ownsRuntime,
    hef: hefObj,
    vdevice: vdevObj,
    networkGroup: ngObj,
    activated: nil,
    inputVstreams: inputVstreams,
    outputVstreams: outputVstreams,
    inputVstream: inputVstream,
    outputVstream: outputVstream,
    inputInfo: inputInfo,
    outputInfo: outputInfo,
    inputFrameSize: inputFrameSize,
    outputFrameSize: outputFrameSize,
    profiling: profiling,
    profile: DetectorProfile()
  ).ok

# ------------------------------------------------------------------------------
#
# openPrepared:
#
# ------------------------------------------------------------------------------
proc openPrepared*(
  _: typedesc[Detector],
  runtime: HailoRuntime,
  hefPath: string,
  hailoNmsScoreThreshold = -1.0'f32,
  profiling = false
): HE[Detector] =
  ## Configure HEF/vstreams on a shared runtime without activating the network.
  ##
  ## Use this for multi-model tests:
  ##   let d = Detector.openPrepared(runtime, "model.hef").get
  ##   d.activate()
  ##   ...
  ##   d.deactivate()
  result = openPreparedWithRuntime(
    runtime,
    hefPath,
    hailoNmsScoreThreshold,
    ownsRuntime = false,
    profiling = profiling
  )

# ------------------------------------------------------------------------------
#
# openPrepared:
#
# ------------------------------------------------------------------------------
proc openPrepared*(
  _: typedesc[Detector],
  hefPath: string,
  hailoNmsScoreThreshold = -1.0'f32,
  schedulingAlgorithm: SchedulingAlgorithm = HAILO_SCHEDULING_ALGORITHM_NONE,
  profiling = false
): HE[Detector] =
  ## Compatibility helper for a single prepared detector with an internally owned
  ## runtime.
  ## The returned detector is not activated yet.
  var runtimeRes = HailoRuntime.open(schedulingAlgorithm)
  if runtimeRes.isErr:
    return runtimeRes.error.err

  result = openPreparedWithRuntime(
    runtimeRes.get,
    hefPath,
    hailoNmsScoreThreshold,
    ownsRuntime = true,
    profiling = profiling
  )

# ------------------------------------------------------------------------------
# Compatibility open APIs:
# ------------------------------------------------------------------------------

proc open*(
  _: typedesc[Detector],
  runtime: HailoRuntime,
  hefPath: string,
  hailoNmsScoreThreshold = -1.0'f32,
  profiling = false
): HE[Detector] =
  ## Backward-compatible shared-runtime open.
  ##
  ## This still activates immediately. Multi-model code should use
  ## Detector.openPrepared(runtime, hefPath) and explicit activate/deactivate.
  let preparedRes = Detector.openPrepared(
    runtime,
    hefPath,
    hailoNmsScoreThreshold,
    profiling = profiling
  )
  if preparedRes.isErr:
    return preparedRes.error.err

  let detector = preparedRes.get
  let actRes = detector.activate()
  if actRes.isErr:
    discard detector.close()
    return actRes.error.err

  result = detector.ok

# ------------------------------------------------------------------------------
#
# open:
#
# ------------------------------------------------------------------------------
proc open*(
  _: typedesc[Detector],
  hefPath: string,
  hailoNmsScoreThreshold = -1.0'f32,
  schedulingAlgorithm: SchedulingAlgorithm = HAILO_SCHEDULING_ALGORITHM_NONE,
  profiling = false
): HE[Detector] =
  ## Existing API: open and activate immediately.
  let preparedRes = Detector.openPrepared(
    hefPath,
    hailoNmsScoreThreshold,
    schedulingAlgorithm,
    profiling = profiling
  )
  if preparedRes.isErr:
    return preparedRes.error.err

  let detector = preparedRes.get
  let actRes = detector.activate()
  if actRes.isErr:
    discard detector.close()
    return actRes.error.err

  result = detector.ok

# ------------------------------------------------------------------------------
# Validation:
# ------------------------------------------------------------------------------

proc validateOutputBuffer(d: Detector; outputLen: int): HE[void] =
  if outputLen == 0:
    return makeError(HAILO_INVALID_ARGUMENT, "output buffer is empty").err

  if outputLen != d.outputFrameSize:
    return makeError(
      HAILO_INVALID_ARGUMENT,
      &"output buffer size mismatch: expected={d.outputFrameSize} actual={outputLen}"
    ).err

  result = okVoid()

# ------------------------------------------------------------------------------
#
# validateActivated:
#
# ------------------------------------------------------------------------------
proc validateActivated(d: Detector): HE[void] =
  if d.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "detector is nil").err
  if d.activated.isNil:
    return makeError(
      HAILO_INVALID_OPERATION,
      "detector is not activated; call activate() before inference"
    ).err

  result = okVoid()

# ------------------------------------------------------------------------------
# Raw inference:
# ------------------------------------------------------------------------------

proc inferRawInto*(
  d: Detector;
  input: openArray[byte];
  output: var openArray[byte]
): HE[void] =
  if d.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "detector is nil").err

  var activatedRes: HE[void]
  var validateInputRes: HE[void]
  var validateOutputRes: HE[void]

  measureProfile(d.profiling, d.profile.validateUs):
    activatedRes = d.validateActivated()
    if activatedRes.isErr:
      return activatedRes.error.err

    validateInputRes = validateInputBuffer(d.inputInfo, input.len)
    if validateInputRes.isErr:
      return validateInputRes.error.err

    validateOutputRes = d.validateOutputBuffer(output.len)
    if validateOutputRes.isErr:
      return validateOutputRes.error.err

  var writeRes: HE[void]
  measureProfile(d.profiling, d.profile.writeUs):
    writeRes = d.inputVstream.write(input)

  if writeRes.isErr:
    return writeRes.error.err

  measureProfile(d.profiling, d.profile.readUs):
    result = d.outputVstream.read(addr output[0], output.len)

  if d.profiling and result.isOk:
    inc d.profile.inferCount

# ------------------------------------------------------------------------------
#
# inferRaw:
#
# ------------------------------------------------------------------------------
proc inferRaw*(d: Detector; input: openArray[byte]): HE[seq[byte]] =
  if d.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "detector is nil").err
  if d.outputFrameSize == 0:
    return makeError(HAILO_INVALID_ARGUMENT, "output size is zero").err

  var output = newSeq[byte](d.outputFrameSize)
  let inferRes = d.inferRawInto(input, output)
  if inferRes.isErr:
    return inferRes.error.err

  result = output.ok

# ------------------------------------------------------------------------------
#
# inferNhwc4Into:
#
# ------------------------------------------------------------------------------
proc inferNhwc4Into*(
  d: Detector;
  input: openArray[byte];
  output: var openArray[byte]
): HE[void] =
  if d.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "detector is nil").err

  var activatedRes: HE[void]
  var validateOutputRes: HE[void]

  measureProfile(d.profiling, d.profile.validateUs):
    activatedRes = d.validateActivated()
    if activatedRes.isErr:
      return activatedRes.error.err

    validateOutputRes = d.validateOutputBuffer(output.len)
    if validateOutputRes.isErr:
      return validateOutputRes.error.err

  var writeRes: HE[void]
  measureProfile(d.profiling, d.profile.writeUs):
    writeRes = d.inputVstream.writeNhwc4(input)

  if writeRes.isErr:
    return writeRes.error.err

  measureProfile(d.profiling, d.profile.readUs):
    result = d.outputVstream.read(addr output[0], output.len)

  if d.profiling and result.isOk:
    inc d.profile.inferCount

# ------------------------------------------------------------------------------
#
# inferNhwc4:
#
# ------------------------------------------------------------------------------
proc inferNhwc4*(d: Detector; input: openArray[byte]): HE[seq[byte]] =
  if d.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "detector is nil").err
  if d.outputFrameSize == 0:
    return makeError(HAILO_INVALID_ARGUMENT, "output size is zero").err

  var output = newSeq[byte](d.outputFrameSize)
  let inferRes = d.inferNhwc4Into(input, output)
  if inferRes.isErr:
    return inferRes.error.err

  result = output.ok

# ------------------------------------------------------------------------------
#
# inferInto:
#
# ------------------------------------------------------------------------------
proc inferInto*(
  d: Detector;
  input: openArray[byte];
  output: var openArray[byte]
): HE[void] =
  if d.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "detector is nil").err

  let mdRes = d.inputMetadata()
  if mdRes.isErr:
    return mdRes.error.err

  let md = mdRes.get
  case md.imageType
  of itNhwc4:
    result = d.inferNhwc4Into(input, output)
  else:
    result = d.inferRawInto(input, output)

# ------------------------------------------------------------------------------
#
# infer:
#
# ------------------------------------------------------------------------------
proc infer*(d: Detector; input: openArray[byte]): HE[seq[byte]] =
  if d.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "detector is nil").err
  if d.outputFrameSize == 0:
    return makeError(HAILO_INVALID_ARGUMENT, "output size is zero").err

  var output = newSeq[byte](d.outputFrameSize)
  let inferRes = d.inferInto(input, output)
  if inferRes.isErr:
    return inferRes.error.err

  result = output.ok

# ------------------------------------------------------------------------------
# NMS detection:
# ------------------------------------------------------------------------------

proc validateNmsByClassOutput(d: Detector): HE[void] =
  if d.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "detector is nil").err

  if d.outputInfo.format.order != HAILO_FORMAT_ORDER_HAILO_NMS_BY_CLASS:
    return makeError(
      HAILO_INVALID_OPERATION,
      &"output format is not HAILO_FORMAT_ORDER_HAILO_NMS_BY_CLASS: got {ord(d.outputInfo.format.order)}"
    ).err

  result = okVoid()

# ------------------------------------------------------------------------------
#
# parseNmsOutputInto:
#
# ------------------------------------------------------------------------------
proc parseNmsOutputInto(
  d: Detector;
  output: openArray[byte];
  detections: var seq[Detection];
  appScoreThreshold: float32
): HE[void] =
  let validateRes = d.validateNmsByClassOutput()
  if validateRes.isErr:
    return validateRes.error.err

  let nmsShape = d.outputInfo.anon0.nms_shape
  let numClasses = int(nmsShape.number_of_classes)
  let maxBoxes = int(nmsShape.max_bboxes_per_class)

  measureProfile(d.profiling, d.profile.parseUs):
    parseNmsByClassVariableInto(
      output,
      numClasses,
      maxBoxes,
      detections,
      appScoreThreshold
    )

  measureProfile(d.profiling, d.profile.sortUs):
    detections.sortByScoreDesc()

  result = okVoid()

# ------------------------------------------------------------------------------
#
# detectNmsByClassInto:
#
# ------------------------------------------------------------------------------
proc detectNmsByClassInto*(
  d: Detector;
  input: openArray[byte];
  outputBuf: var openArray[byte];
  detections: var seq[Detection];
  appScoreThreshold = 0.25'f32
): HE[void] =
  if d.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "detector is nil").err

  let validateRes = d.validateNmsByClassOutput()
  if validateRes.isErr:
    return validateRes.error.err

  let inferRes = d.inferRawInto(input, outputBuf)
  if inferRes.isErr:
    return inferRes.error.err

  result = d.parseNmsOutputInto(outputBuf, detections, appScoreThreshold)

# ------------------------------------------------------------------------------
#
# detectNmsByClassNhwc4Into:
#
# ------------------------------------------------------------------------------
proc detectNmsByClassNhwc4Into*(
  d: Detector;
  input: openArray[byte];
  outputBuf: var openArray[byte];
  detections: var seq[Detection];
  appScoreThreshold = 0.25'f32
): HE[void] =
  if d.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "detector is nil").err

  let validateRes = d.validateNmsByClassOutput()
  if validateRes.isErr:
    return validateRes.error.err

  let inferRes = d.inferNhwc4Into(input, outputBuf)
  if inferRes.isErr:
    return inferRes.error.err

  result = d.parseNmsOutputInto(outputBuf, detections, appScoreThreshold)

# ------------------------------------------------------------------------------
#
# detectNmsByClassAutoInto:
#
# ------------------------------------------------------------------------------
proc detectNmsByClassAutoInto*(
  d: Detector;
  input: openArray[byte];
  outputBuf: var openArray[byte];
  detections: var seq[Detection];
  appScoreThreshold = 0.25'f32
): HE[void] =
  if d.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "detector is nil").err

  let mdRes = d.inputMetadata()
  if mdRes.isErr:
    return mdRes.error.err

  let md = mdRes.get
  case md.imageType
  of itNhwc4:
    result = d.detectNmsByClassNhwc4Into(
      input,
      outputBuf,
      detections,
      appScoreThreshold
    )
  else:
    result = d.detectNmsByClassInto(
      input,
      outputBuf,
      detections,
      appScoreThreshold
    )

# ------------------------------------------------------------------------------
#
# detectNmsByClass:
#
# ------------------------------------------------------------------------------
proc detectNmsByClass*(
  d: Detector,
  input: openArray[byte],
  appScoreThreshold = 0.25'f32
): HE[seq[Detection]] =
  if d.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "detector is nil").err
  if d.outputFrameSize == 0:
    return makeError(HAILO_INVALID_ARGUMENT, "output size is zero").err

  var outputBuf = newSeq[byte](d.outputFrameSize)
  var detections: seq[Detection] = @[]

  let detectRes = d.detectNmsByClassInto(
    input,
    outputBuf,
    detections,
    appScoreThreshold
  )
  if detectRes.isErr:
    return detectRes.error.err

  result = detections.ok

# ------------------------------------------------------------------------------
#
# detectNmsByClassNhwc4:
#
# ------------------------------------------------------------------------------
proc detectNmsByClassNhwc4*(
  d: Detector,
  input: openArray[byte],
  appScoreThreshold = 0.25'f32
): HE[seq[Detection]] =
  if d.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "detector is nil").err
  if d.outputFrameSize == 0:
    return makeError(HAILO_INVALID_ARGUMENT, "output size is zero").err

  var outputBuf = newSeq[byte](d.outputFrameSize)
  var detections: seq[Detection] = @[]

  let detectRes = d.detectNmsByClassNhwc4Into(
    input,
    outputBuf,
    detections,
    appScoreThreshold
  )
  if detectRes.isErr:
    return detectRes.error.err

  result = detections.ok

# ------------------------------------------------------------------------------
#
# detectNmsByClassAuto:
#
# ------------------------------------------------------------------------------
proc detectNmsByClassAuto*(
  d: Detector,
  input: openArray[byte],
  appScoreThreshold = 0.25'f32
): HE[seq[Detection]] =
  if d.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "detector is nil").err
  if d.outputFrameSize == 0:
    return makeError(HAILO_INVALID_ARGUMENT, "output size is zero").err

  var outputBuf = newSeq[byte](d.outputFrameSize)
  var detections: seq[Detection] = @[]

  let detectRes = d.detectNmsByClassAutoInto(
    input,
    outputBuf,
    detections,
    appScoreThreshold
  )
  if detectRes.isErr:
    return detectRes.error.err

  result = detections.ok
