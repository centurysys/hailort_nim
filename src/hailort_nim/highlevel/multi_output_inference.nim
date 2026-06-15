import std/[monotimes, strformat, times]

import ../lowlevel

# ==============================================================================
# Public types
# ==============================================================================

type
  MultiOutputInferenceProfile* = object
    inferCount*: int
    validateUs*: int64
    writeUs*: int64
    readUs*: int64

  MultiOutputInferenceOutput* = object
    index*: int
    data*: seq[byte]
    readUs*: int64

  MultiOutputInferenceResult* = object
    writeUs*: int64
    readUs*: int64
    outputs*: seq[MultiOutputInferenceOutput]

  MultiOutputInference* = ref object
    ## A high-level inference helper for models with one input vstream and one
    ## or more output vstreams.
    ##
    ## This is intentionally raw-output focused.  It is useful for inspecting
    ## custom HEFs and multi-head models before adding a model-specific parser.
    runtime*: HailoRuntime
    ownsRuntime*: bool
    hef*: Hef
    vdevice*: Vdevice
    networkGroup*: NetworkGroup
    activated*: ActivatedNetworkGroup
    inputVstreams*: InputVStreams
    outputVstreams*: OutputVStreams
    inputVstream*: InputVStream
    inputInfo*: VstreamInfo
    outputInfos*: seq[VstreamInfo]
    inputFrameSize*: int
    outputFrameSizes*: seq[int]
    outputFormatType*: hailo_format_type_t
    batchSize*: uint16
    profiling*: bool
    profile*: MultiOutputInferenceProfile

# ==============================================================================
# Small helpers
# ==============================================================================

proc elapsedUs(started: MonoTime): int64 {.inline.} =
  result = inMicroseconds(getMonoTime() - started)

proc addElapsedUs(dst: var int64; started: MonoTime) {.inline.} =
  dst += elapsedUs(started)

template measureProfile(enabled: bool; dst: var int64; body: untyped): untyped =
  if enabled:
    let t0 = getMonoTime()
    body
    dst.addElapsedUs(t0)
  else:
    body

proc formatTypeName*(formatType: hailo_format_type_t): string =
  result = case formatType
    of HAILO_FORMAT_TYPE_AUTO:
      "AUTO"
    of HAILO_FORMAT_TYPE_UINT8:
      "UINT8"
    of HAILO_FORMAT_TYPE_UINT16:
      "UINT16"
    of HAILO_FORMAT_TYPE_FLOAT32:
      "FLOAT32"
    else:
      "UNKNOWN"

# ==============================================================================
# Lifecycle
# ==============================================================================

proc resetProfile*(m: MultiOutputInference) =
  if m.isNil:
    return

  m.profile = MultiOutputInferenceProfile()

proc enableProfiling*(m: MultiOutputInference; enabled = true; reset = true) =
  if m.isNil:
    return

  m.profiling = enabled
  if reset:
    m.resetProfile()

proc disableProfiling*(m: MultiOutputInference; reset = false) =
  if m.isNil:
    return

  m.profiling = false
  if reset:
    m.resetProfile()

proc avgMs(totalUs: int64; count: int): float =
  if count <= 0:
    result = 0.0
  else:
    result = float(totalUs) / float(count) / 1000.0

proc profileSummary*(m: MultiOutputInference): string =
  if m.isNil:
    return "hailort_multi_output_profile model=nil"

  let p = m.profile
  let totalUs = p.validateUs + p.writeUs + p.readUs

  result =
    &"hailort_multi_output_profile count={p.inferCount} " &
    &"avg_ms total={avgMs(totalUs, p.inferCount):.3f} " &
    &"validate={avgMs(p.validateUs, p.inferCount):.3f} " &
    &"write={avgMs(p.writeUs, p.inferCount):.3f} " &
    &"read={avgMs(p.readUs, p.inferCount):.3f}"

proc activate*(m: MultiOutputInference): HE[void] =
  if m.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "multi-output inference is nil").err

  if m.networkGroup.isNil:
    return makeError(HAILO_INVALID_OPERATION, "network group is nil").err

  if not m.activated.isNil:
    return okVoid()

  let activatedRes = m.networkGroup.activate()
  if activatedRes.isErr:
    return activatedRes.error.err

  m.activated = activatedRes.get
  result = okVoid()

proc deactivate*(m: MultiOutputInference): HE[void] =
  if m.isNil:
    return okVoid()

  if m.activated.isNil:
    return okVoid()

  let res = m.activated.close()
  if res.isErr:
    return res

  m.activated = nil
  result = okVoid()

proc close*(m: MultiOutputInference): HE[void] =
  if m.isNil:
    return okVoid()

  let deactRes = m.deactivate()
  if deactRes.isErr:
    return deactRes

  if not m.inputVstreams.isNil:
    let res = m.inputVstreams.close()
    if res.isErr:
      return res

  if not m.outputVstreams.isNil:
    let res = m.outputVstreams.close()
    if res.isErr:
      return res

  if not m.networkGroup.isNil:
    let res = m.networkGroup.close()
    if res.isErr:
      return res

  if not m.hef.isNil:
    let res = m.hef.close()
    if res.isErr:
      return res

  if m.ownsRuntime and not m.runtime.isNil:
    let res = m.runtime.close()
    if res.isErr:
      return res
  elif m.runtime.isNil and not m.vdevice.isNil:
    let res = m.vdevice.close()
    if res.isErr:
      return res

  m.activated = nil
  m.inputVstreams = nil
  m.outputVstreams = nil
  m.inputVstream = nil
  m.inputInfo = VstreamInfo()
  m.outputInfos.setLen(0)
  m.outputFrameSizes.setLen(0)
  m.inputFrameSize = 0
  m.outputFormatType = HAILO_FORMAT_TYPE_AUTO
  m.networkGroup = nil
  m.vdevice = nil
  m.hef = nil
  m.runtime = nil
  m.ownsRuntime = false
  m.batchSize = uint16(HAILO_DEFAULT_BATCH_SIZE)

  result = okVoid()

# ==============================================================================
# Open helpers
# ==============================================================================

proc openPreparedWithRuntime(
  runtime: HailoRuntime,
  hefPath: string,
  ownsRuntime: bool,
  profiling = false,
  outputFormatType: hailo_format_type_t = HAILO_FORMAT_TYPE_AUTO,
  batchSize: uint16 = uint16(HAILO_DEFAULT_BATCH_SIZE)
): HE[MultiOutputInference] =
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

  let ngRes = configureOne(vdevObj, hefObj, batchSize)
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

  let outputParamsRes = makeOutputVstreamParams(ngObj, outputFormatType)
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
      &"MultiOutputInference currently expects exactly 1 input vstream, got {inputParams.len}"
    ).err

  if outputParams.len == 0:
    discard ngObj.close()
    discard hefObj.close()
    if ownsRuntime:
      discard runtime.close()
    return makeError(HAILO_INVALID_OPERATION, "HEF has no output vstreams").err

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

  let inputFrameSizeRes = inputVstream.frameSize()
  if inputFrameSizeRes.isErr:
    discard outputVstreams.close()
    discard inputVstreams.close()
    discard ngObj.close()
    discard hefObj.close()
    if ownsRuntime:
      discard runtime.close()
    return inputFrameSizeRes.error.err

  var outputInfos = newSeq[VstreamInfo](outputVstreams.len)
  var outputFrameSizes = newSeq[int](outputVstreams.len)

  for i in 0 ..< outputVstreams.len:
    let outputInfoRes = outputVstreams[i].info()
    if outputInfoRes.isErr:
      discard outputVstreams.close()
      discard inputVstreams.close()
      discard ngObj.close()
      discard hefObj.close()
      if ownsRuntime:
        discard runtime.close()
      return outputInfoRes.error.err

    let outputFrameSizeRes = outputVstreams[i].frameSize()
    if outputFrameSizeRes.isErr:
      discard outputVstreams.close()
      discard inputVstreams.close()
      discard ngObj.close()
      discard hefObj.close()
      if ownsRuntime:
        discard runtime.close()
      return outputFrameSizeRes.error.err

    outputInfos[i] = outputInfoRes.get
    outputFrameSizes[i] = outputFrameSizeRes.get

  result = MultiOutputInference(
    runtime: runtime,
    ownsRuntime: ownsRuntime,
    hef: hefObj,
    vdevice: vdevObj,
    networkGroup: ngObj,
    activated: nil,
    inputVstreams: inputVstreams,
    outputVstreams: outputVstreams,
    inputVstream: inputVstream,
    inputInfo: inputInfo,
    outputInfos: outputInfos,
    inputFrameSize: inputFrameSizeRes.get,
    outputFrameSizes: outputFrameSizes,
    outputFormatType: outputFormatType,
    batchSize: batchSize,
    profiling: profiling,
    profile: MultiOutputInferenceProfile()
  ).ok

proc openPrepared*(
  _: typedesc[MultiOutputInference],
  runtime: HailoRuntime,
  hefPath: string,
  profiling = false,
  outputFormatType: hailo_format_type_t = HAILO_FORMAT_TYPE_AUTO,
  batchSize: uint16 = uint16(HAILO_DEFAULT_BATCH_SIZE)
): HE[MultiOutputInference] =
  result = openPreparedWithRuntime(
    runtime,
    hefPath,
    ownsRuntime = false,
    profiling = profiling,
    outputFormatType = outputFormatType,
    batchSize = batchSize
  )

proc openPrepared*(
  _: typedesc[MultiOutputInference],
  hefPath: string,
  schedulingAlgorithm: SchedulingAlgorithm = HAILO_SCHEDULING_ALGORITHM_NONE,
  profiling = false,
  outputFormatType: hailo_format_type_t = HAILO_FORMAT_TYPE_AUTO,
  batchSize: uint16 = uint16(HAILO_DEFAULT_BATCH_SIZE)
): HE[MultiOutputInference] =
  var runtimeRes = HailoRuntime.open(schedulingAlgorithm)
  if runtimeRes.isErr:
    return runtimeRes.error.err

  result = openPreparedWithRuntime(
    runtimeRes.get,
    hefPath,
    ownsRuntime = true,
    profiling = profiling,
    outputFormatType = outputFormatType,
    batchSize = batchSize
  )

proc open*(
  _: typedesc[MultiOutputInference],
  runtime: HailoRuntime,
  hefPath: string,
  profiling = false,
  outputFormatType: hailo_format_type_t = HAILO_FORMAT_TYPE_AUTO,
  batchSize: uint16 = uint16(HAILO_DEFAULT_BATCH_SIZE)
): HE[MultiOutputInference] =
  let preparedRes = MultiOutputInference.openPrepared(
    runtime,
    hefPath,
    profiling = profiling,
    outputFormatType = outputFormatType,
    batchSize = batchSize
  )
  if preparedRes.isErr:
    return preparedRes.error.err

  let model = preparedRes.get
  let actRes = model.activate()
  if actRes.isErr:
    discard model.close()
    return actRes.error.err

  result = model.ok

proc open*(
  _: typedesc[MultiOutputInference],
  hefPath: string,
  schedulingAlgorithm: SchedulingAlgorithm = HAILO_SCHEDULING_ALGORITHM_NONE,
  profiling = false,
  outputFormatType: hailo_format_type_t = HAILO_FORMAT_TYPE_AUTO,
  batchSize: uint16 = uint16(HAILO_DEFAULT_BATCH_SIZE)
): HE[MultiOutputInference] =
  let preparedRes = MultiOutputInference.openPrepared(
    hefPath,
    schedulingAlgorithm,
    profiling = profiling,
    outputFormatType = outputFormatType,
    batchSize = batchSize
  )
  if preparedRes.isErr:
    return preparedRes.error.err

  let model = preparedRes.get
  let actRes = model.activate()
  if actRes.isErr:
    discard model.close()
    return actRes.error.err

  result = model.ok

# ==============================================================================
# Introspection
# ==============================================================================

proc isActivated*(m: MultiOutputInference): bool {.inline.} =
  result = (not m.isNil) and (not m.activated.isNil)

proc inputSize*(m: MultiOutputInference): int {.inline.} =
  if m.isNil: 0 else: m.inputFrameSize

proc outputCount*(m: MultiOutputInference): int {.inline.} =
  if m.isNil: 0 else: m.outputFrameSizes.len

proc outputSize*(m: MultiOutputInference; index: int): int =
  if m.isNil or index < 0 or index >= m.outputFrameSizes.len:
    return 0

  result = m.outputFrameSizes[index]

proc totalOutputSize*(m: MultiOutputInference): int =
  if m.isNil:
    return 0

  for size in m.outputFrameSizes:
    result += size

proc requestedOutputFormatType*(m: MultiOutputInference): hailo_format_type_t {.inline.} =
  if m.isNil:
    HAILO_FORMAT_TYPE_AUTO
  else:
    m.outputFormatType

proc requestedOutputFormatName*(m: MultiOutputInference): string {.inline.} =
  formatTypeName(m.requestedOutputFormatType())

proc configuredBatchSize*(m: MultiOutputInference): uint16 {.inline.} =
  if m.isNil:
    uint16(HAILO_DEFAULT_BATCH_SIZE)
  else:
    m.batchSize

proc outputUserFormat*(m: MultiOutputInference; index: int): HE[Format] =
  if m.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "multi-output inference is nil").err

  if index < 0 or index >= m.outputVstreams.len:
    return makeError(
      HAILO_INVALID_ARGUMENT,
      &"output index out of range: index={index} count={m.outputVstreams.len}"
    ).err

  result = m.outputVstreams[index].userBufferFormat()

proc outputUserFormats*(m: MultiOutputInference): HE[seq[Format]] =
  if m.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "multi-output inference is nil").err

  var formats = newSeq[Format](m.outputVstreams.len)
  for i in 0 ..< m.outputVstreams.len:
    let fmtRes = m.outputVstreams[i].userBufferFormat()
    if fmtRes.isErr:
      return fmtRes.error.err
    formats[i] = fmtRes.get

  result = formats.ok

proc inputMetadata*(m: MultiOutputInference): HE[VStreamMetadata] =
  if m.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "multi-output inference is nil").err

  result = m.inputInfo.metadata().ok

proc outputMetadata*(m: MultiOutputInference; index: int): HE[VStreamMetadata] =
  if m.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "multi-output inference is nil").err

  if index < 0 or index >= m.outputInfos.len:
    return makeError(
      HAILO_INVALID_ARGUMENT,
      &"output index out of range: index={index} count={m.outputInfos.len}"
    ).err

  result = m.outputInfos[index].metadata().ok

proc outputMetadatas*(m: MultiOutputInference): HE[seq[VStreamMetadata]] =
  if m.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "multi-output inference is nil").err

  var metas = newSeq[VStreamMetadata](m.outputInfos.len)
  for i in 0 ..< m.outputInfos.len:
    metas[i] = m.outputInfos[i].metadata()

  result = metas.ok

# ==============================================================================
# Raw inference
# ==============================================================================

proc validateActivated(m: MultiOutputInference): HE[void] =
  if m.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "multi-output inference is nil").err

  if m.activated.isNil:
    return makeError(
      HAILO_INVALID_OPERATION,
      "multi-output inference is not activated; call activate() before inference"
    ).err

  result = okVoid()

proc inferRawInto*(
  m: MultiOutputInference;
  input: openArray[byte];
  outputs: var seq[seq[byte]]
): HE[MultiOutputInferenceResult] =
  if m.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "multi-output inference is nil").err

  var activatedRes: HE[void]
  var validateInputRes: HE[void]

  measureProfile(m.profiling, m.profile.validateUs):
    activatedRes = m.validateActivated()
    if activatedRes.isErr:
      return activatedRes.error.err

    validateInputRes = validateInputBuffer(m.inputInfo, input.len)
    if validateInputRes.isErr:
      return validateInputRes.error.err

  if outputs.len != m.outputCount():
    outputs.setLen(m.outputCount())

  for i in 0 ..< m.outputCount():
    if outputs[i].len != m.outputFrameSizes[i]:
      outputs[i].setLen(m.outputFrameSizes[i])

  var writeRes: HE[void]
  var writeUs: int64
  var writeStarted = getMonoTime()
  measureProfile(m.profiling, m.profile.writeUs):
    writeStarted = getMonoTime()
    writeRes = m.inputVstream.write(input)
    writeUs = elapsedUs(writeStarted)

  if writeRes.isErr:
    return writeRes.error.err

  var outItems = newSeq[MultiOutputInferenceOutput](m.outputCount())
  var totalReadUs: int64 = 0

  measureProfile(m.profiling, m.profile.readUs):
    for i in 0 ..< m.outputCount():
      let readStarted = getMonoTime()
      let readRes = m.outputVstreams[i].read(addr outputs[i][0], outputs[i].len)
      let readUs = elapsedUs(readStarted)
      if readRes.isErr:
        return readRes.error.err

      totalReadUs += readUs
      outItems[i] = MultiOutputInferenceOutput(
        index: i,
        data: outputs[i],
        readUs: readUs
      )

  if m.profiling:
    inc m.profile.inferCount

  result = MultiOutputInferenceResult(
    writeUs: writeUs,
    readUs: totalReadUs,
    outputs: outItems
  ).ok

proc inferRaw*(m: MultiOutputInference; input: openArray[byte]): HE[MultiOutputInferenceResult] =
  if m.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "multi-output inference is nil").err

  var outputs: seq[seq[byte]]
  result = m.inferRawInto(input, outputs)
