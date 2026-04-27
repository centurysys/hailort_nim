import std/[algorithm, strformat]

import ../lowlevel
import ../models/detection

type
  Detector* = ref object
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

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc readF32Le(data: openArray[byte]; offset: int): float32 =
  if offset + 4 > data.len:
    raise newException(ValueError, "readF32Le: offset out of range")
  copyMem(addr result, unsafeAddr data[offset], 4)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc parseNmsByClassVariableInto*(raw: openArray[byte], numberOfClasses: int,
    maxBboxesPerClass: int, detections: var seq[Detection],
    appScoreThreshold = 0.25'f32) =
  ## Parse HAILO_FORMAT_ORDER_HAILO_NMS_BY_CLASS variable-length layout into
  ## a caller-provided detection sequence.
  ##
  ## The sequence is cleared but its capacity is kept, allowing callers to reuse
  ## the same storage across streaming inference loops.
  detections.setLen(0)

  var offset = 0
  let rawLen = raw.len

  for classId in 0..<numberOfClasses:
    if offset + 4 > rawLen:
      return

    let countF = readF32Le(raw, offset)
    offset += 4

    var count = int(countF)
    if count < 0:
      count = 0
    if count > maxBboxesPerClass:
      count = maxBboxesPerClass

    for _ in 0..<count:
      if offset + 20 > rawLen:
        return

      let yMin = readF32Le(raw, offset + 0)
      let xMin = readF32Le(raw, offset + 4)
      let yMax = readF32Le(raw, offset + 8)
      let xMax = readF32Le(raw, offset + 12)
      let score = readF32Le(raw, offset + 16)
      offset += 20

      if appScoreThreshold <= 0 or score >= appScoreThreshold:
        let detection = Detection(classId: classId, score: score,
            yMin: yMin, xMin: xMin, yMax: yMax, xMax: xMax)
        detections.add(detection)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc parseNmsByClassVariable*(raw: openArray[byte], numberOfClasses: int,
    maxBboxesPerClass: int, appScoreThreshold = 0.25'f32): seq[Detection] =
  ## Parse HAILO_FORMAT_ORDER_HAILO_NMS_BY_CLASS variable-length layout.
  ##
  ## This allocation-returning wrapper is kept for compatibility. Streaming code
  ## should prefer parseNmsByClassVariableInto().
  parseNmsByClassVariableInto(
    raw,
    numberOfClasses,
    maxBboxesPerClass,
    result,
    appScoreThreshold
  )

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc sortByScoreDesc*(detections: var seq[Detection]) =
  detections.sort(proc(a, b: Detection): int = cmp(b.score, a.score))

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc inputSize*(d: Detector): int {.inline.} =
  d.inputFrameSize

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc outputSize*(d: Detector): int {.inline.} =
  d.outputFrameSize

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc inputMetadata*(d: Detector): HE[VStreamMetadata] =
  if d.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "detector is nil").err
  result = d.inputInfo.metadata().ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc outputMetadata*(d: Detector): HE[VStreamMetadata] =
  if d.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "detector is nil").err
  result = d.outputInfo.metadata().ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc inputShape*(d: Detector): HE[ImageShape] =
  let mdRes = d.inputMetadata()
  if mdRes.isErr:
    return mdRes.error.err
  result = mdRes.get.shape.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc outputShape*(d: Detector): HE[ImageShape] =
  let mdRes = d.outputMetadata()
  if mdRes.isErr:
    return mdRes.error.err
  result = mdRes.get.shape.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc inputPixelFormat*(d: Detector): HE[PixelFormat] =
  let mdRes = d.inputMetadata()
  if mdRes.isErr:
    return mdRes.error.err
  result = mdRes.get.pixelFormat.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc outputPixelFormat*(d: Detector): HE[PixelFormat] =
  let mdRes = d.outputMetadata()
  if mdRes.isErr:
    return mdRes.error.err
  result = mdRes.get.pixelFormat.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc inputImageType*(d: Detector): HE[ImageType] =
  let mdRes = d.inputMetadata()
  if mdRes.isErr:
    return mdRes.error.err
  result = mdRes.get.imageType.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc outputImageType*(d: Detector): HE[ImageType] =
  let mdRes = d.outputMetadata()
  if mdRes.isErr:
    return mdRes.error.err
  result = mdRes.get.imageType.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc close*(d: Detector): HE[void] =
  if d.isNil:
    return okVoid()

  if not d.activated.isNil:
    let res = d.activated.close()
    if res.isErr:
      return res

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

  if not d.vdevice.isNil:
    let res = d.vdevice.close()
    if res.isErr:
      return res

  if not d.hef.isNil:
    let res = d.hef.close()
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

  okVoid()

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc open*(_: typedesc[Detector], hefPath: string,
    hailoNmsScoreThreshold = -1.0'f32,
    schedulingAlgorithm: SchedulingAlgorithm =
        HAILO_SCHEDULING_ALGORITHM_NONE): HE[Detector] =
  let hefRes = openHef(hefPath)
  if hefRes.isErr:
    return hefRes.error.err
  let hefObj = hefRes.get

  var vdevParamsRes = initVdeviceParams()
  if vdevParamsRes.isErr:
    discard hefObj.close()
    return vdevParamsRes.error.err
  var vdevParams = vdevParamsRes.get
  vdevParams.scheduling_algorithm = schedulingAlgorithm

  let vdevRes = createVdevice(vdevParams)
  if vdevRes.isErr:
    discard hefObj.close()
    return vdevRes.error.err
  let vdevObj = vdevRes.get

  let ngRes = configureOne(vdevObj, hefObj)
  if ngRes.isErr:
    discard vdevObj.close()
    discard hefObj.close()
    return ngRes.error.err
  let ngObj = ngRes.get

  let inputParamsRes = makeInputVstreamParams(ngObj)
  if inputParamsRes.isErr:
    discard ngObj.close()
    discard vdevObj.close()
    discard hefObj.close()
    return inputParamsRes.error.err
  let inputParams = inputParamsRes.get

  let outputParamsRes = makeOutputVstreamParams(ngObj)
  if outputParamsRes.isErr:
    discard ngObj.close()
    discard vdevObj.close()
    discard hefObj.close()
    return outputParamsRes.error.err
  let outputParams = outputParamsRes.get

  if inputParams.len != 1:
    discard ngObj.close()
    discard vdevObj.close()
    discard hefObj.close()
    return makeError(
      HAILO_INVALID_OPERATION,
      &"Detector currently expects exactly 1 input vstream, got {inputParams.len}"
    ).err

  if outputParams.len != 1:
    discard ngObj.close()
    discard vdevObj.close()
    discard hefObj.close()
    return makeError(
      HAILO_INVALID_OPERATION,
      &"Detector currently expects exactly 1 output vstream, got {outputParams.len}"
    ).err

  let inputVstreamsRes = createInputVstreams(ngObj, inputParams)
  if inputVstreamsRes.isErr:
    discard ngObj.close()
    discard vdevObj.close()
    discard hefObj.close()
    return inputVstreamsRes.error.err
  let inputVstreams = inputVstreamsRes.get

  let outputVstreamsRes = createOutputVstreams(ngObj, outputParams)
  if outputVstreamsRes.isErr:
    discard inputVstreams.close()
    discard ngObj.close()
    discard vdevObj.close()
    discard hefObj.close()
    return outputVstreamsRes.error.err
  let outputVstreams = outputVstreamsRes.get

  let inputVstream = inputVstreams[0]
  let outputVstream = outputVstreams[0]

  let inputInfoRes = inputVstream.info()
  if inputInfoRes.isErr:
    discard outputVstreams.close()
    discard inputVstreams.close()
    discard ngObj.close()
    discard vdevObj.close()
    discard hefObj.close()
    return inputInfoRes.error.err
  let inputInfo = inputInfoRes.get

  let outputInfoRes = outputVstream.info()
  if outputInfoRes.isErr:
    discard outputVstreams.close()
    discard inputVstreams.close()
    discard ngObj.close()
    discard vdevObj.close()
    discard hefObj.close()
    return outputInfoRes.error.err
  let outputInfo = outputInfoRes.get

  let inputFrameSizeRes = inputVstream.frameSize()
  if inputFrameSizeRes.isErr:
    discard outputVstreams.close()
    discard inputVstreams.close()
    discard ngObj.close()
    discard vdevObj.close()
    discard hefObj.close()
    return inputFrameSizeRes.error.err
  let inputFrameSize = inputFrameSizeRes.get

  let outputFrameSizeRes = outputVstream.frameSize()
  if outputFrameSizeRes.isErr:
    discard outputVstreams.close()
    discard inputVstreams.close()
    discard ngObj.close()
    discard vdevObj.close()
    discard hefObj.close()
    return outputFrameSizeRes.error.err
  let outputFrameSize = outputFrameSizeRes.get

  if hailoNmsScoreThreshold >= 0:
    let setThRes = outputVstream.setNmsScoreThreshold(hailoNmsScoreThreshold)
    if setThRes.isErr:
      discard outputVstreams.close()
      discard inputVstreams.close()
      discard ngObj.close()
      discard vdevObj.close()
      discard hefObj.close()
      return setThRes.error.err

  let activatedRes = ngObj.activate()
  if activatedRes.isErr:
    discard outputVstreams.close()
    discard inputVstreams.close()
    discard ngObj.close()
    discard vdevObj.close()
    discard hefObj.close()
    return activatedRes.error.err

  result = Detector(
    hef: hefObj,
    vdevice: vdevObj,
    networkGroup: ngObj,
    activated: activatedRes.get,
    inputVstreams: inputVstreams,
    outputVstreams: outputVstreams,
    inputVstream: inputVstream,
    outputVstream: outputVstream,
    inputInfo: inputInfo,
    outputInfo: outputInfo,
    inputFrameSize: inputFrameSize,
    outputFrameSize: outputFrameSize
  ).ok

# ------------------------------------------------------------------------------
#
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
# ------------------------------------------------------------------------------
proc inferRawInto*(d: Detector; input: openArray[byte];
    output: var openArray[byte]): HE[void] =
  if d.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "detector is nil").err

  let validateInputRes = validateInputBuffer(d.inputInfo, input.len)
  if validateInputRes.isErr:
    return validateInputRes.error.err

  let validateOutputRes = d.validateOutputBuffer(output.len)
  if validateOutputRes.isErr:
    return validateOutputRes.error.err

  let writeRes = d.inputVstream.write(input)
  if writeRes.isErr:
    return writeRes.error.err

  result = d.outputVstream.read(addr output[0], output.len)

# ------------------------------------------------------------------------------
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
# ------------------------------------------------------------------------------
proc inferNhwc4Into*(d: Detector; input: openArray[byte];
    output: var openArray[byte]): HE[void] =
  if d.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "detector is nil").err

  let validateOutputRes = d.validateOutputBuffer(output.len)
  if validateOutputRes.isErr:
    return validateOutputRes.error.err

  let writeRes = d.inputVstream.writeNhwc4(input)
  if writeRes.isErr:
    return writeRes.error.err

  result = d.outputVstream.read(addr output[0], output.len)

# ------------------------------------------------------------------------------
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
# ------------------------------------------------------------------------------
proc inferInto*(d: Detector; input: openArray[byte];
    output: var openArray[byte]): HE[void] =
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
#
# ------------------------------------------------------------------------------
proc detectNmsByClass*(d: Detector, input: openArray[byte],
    appScoreThreshold = 0.25'f32): HE[seq[Detection]] =
  if d.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "detector is nil").err

  if d.outputInfo.format.order != HAILO_FORMAT_ORDER_HAILO_NMS_BY_CLASS:
    return makeError(
      HAILO_INVALID_OPERATION,
      &"output format is not HAILO_FORMAT_ORDER_HAILO_NMS_BY_CLASS: got {ord(d.outputInfo.format.order)}"
    ).err

  let rawRes = d.inferRaw(input)
  if rawRes.isErr:
    return rawRes.error.err

  let nmsShape = d.outputInfo.anon0.nms_shape
  let numClasses = int(nmsShape.number_of_classes)
  let maxBoxes = int(nmsShape.max_bboxes_per_class)

  var detections = parseNmsByClassVariable(
    rawRes.get,
    numClasses,
    maxBoxes,
    appScoreThreshold
  )
  detections.sortByScoreDesc()
  result = detections.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc detectNmsByClassNhwc4*(d: Detector, input: openArray[byte],
    appScoreThreshold = 0.25'f32): HE[seq[Detection]] =
  if d.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "detector is nil").err

  if d.outputInfo.format.order != HAILO_FORMAT_ORDER_HAILO_NMS_BY_CLASS:
    return makeError(
      HAILO_INVALID_OPERATION,
      &"output format is not HAILO_FORMAT_ORDER_HAILO_NMS_BY_CLASS: got {ord(d.outputInfo.format.order)}"
    ).err

  let rawRes = d.inferNhwc4(input)
  if rawRes.isErr:
    return rawRes.error.err

  let nmsShape = d.outputInfo.anon0.nms_shape
  let numClasses = int(nmsShape.number_of_classes)
  let maxBoxes = int(nmsShape.max_bboxes_per_class)

  var detections = parseNmsByClassVariable(
    rawRes.get,
    numClasses,
    maxBoxes,
    appScoreThreshold
  )
  detections.sortByScoreDesc()
  result = detections.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc detectNmsByClassAuto*(d: Detector, input: openArray[byte],
    appScoreThreshold = 0.25'f32): HE[seq[Detection]] =
  if d.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "detector is nil").err

  let mdRes = d.inputMetadata()
  if mdRes.isErr:
    return mdRes.error.err
  let md = mdRes.get

  case md.imageType
  of itNhwc4:
    result = d.detectNmsByClassNhwc4(input, appScoreThreshold)
  of itNhwc3, itUnknown:
    result = d.detectNmsByClass(input, appScoreThreshold)
  else:
    result = d.detectNmsByClass(input, appScoreThreshold)
