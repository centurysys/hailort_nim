import std/[monotimes, strformat, times]

import ./detector
import ./inference_result
import ./text_detection_parser
import ../lowlevel
import ../models/detection

# ==============================================================================
# Generic output parser configuration
# ==============================================================================

type
  HailoOutputParserKind* = enum
    ## Parser kind for converting a HAILO output buffer into HailoInferenceResult.
    ##
    ## hopRawTensor, hopNmsByClass, and hopTextDetectionDb are implemented.
    ## The remaining values are reserved so worker/app code can name the
    ## intended future parser without forcing another public enum reshuffle.
    hopRawTensor
    hopNmsByClass
    hopClassificationTopK
    hopTextDetectionDb
    hopTextRecognition

  HailoOutputParserConfig* = object
    ## Parser configuration shared by the future ThreadtoolsInferenceWorker.
    ##
    ## Raw tensor parsing copies the output bytes, making the result independent
    ## from ThreadtoolsVStreamRunner slot lifetime.  NMS parsing reads the output
    ## slot directly and only stores parsed Detection values.
    kind*: HailoOutputParserKind
    outputNameOverride*: string
    maxRawTensorBytes*: int
    numberOfClasses*: int
    maxBboxesPerClass*: int
    appScoreThreshold*: float32
    sortDetections*: bool
    textDetection*: TextDetectionParserConfig

# ==============================================================================
# Small helpers
# ==============================================================================

proc elapsedUs(started: MonoTime): int64 {.inline.} =
  result = inMicroseconds(getMonoTime() - started)

proc effectiveOutputName(
  config: HailoOutputParserConfig;
  metadata: VStreamMetadata
): string =
  ## Return a physically independent output name.
  ##
  ## Parser config and metadata are stored in worker state and then read from the
  ## worker thread. Returning a cloned string avoids moving a reply that aliases
  ## string storage owned by the worker state or by the caller thread.
  if config.outputNameOverride.len > 0:
    result = cloneString(config.outputNameOverride)
  else:
    result = cloneString(metadata.name)

proc implemented*(kind: HailoOutputParserKind): bool =
  result = case kind
    of hopRawTensor, hopNmsByClass, hopTextDetectionDb:
      true
    of hopClassificationTopK, hopTextRecognition:
      false

proc validateParserConfig*(config: HailoOutputParserConfig): HE[void] =
  if not config.kind.implemented():
    return makeError(
      HAILO_NOT_SUPPORTED,
      &"parser kind is not implemented yet: {config.kind}"
    ).err

  case config.kind
  of hopRawTensor:
    if config.maxRawTensorBytes < 0:
      return makeError(
        HAILO_INVALID_ARGUMENT,
        &"maxRawTensorBytes must be >= 0: {config.maxRawTensorBytes}"
      ).err

  of hopNmsByClass:
    if config.numberOfClasses <= 0:
      return makeError(
        HAILO_INVALID_ARGUMENT,
        &"numberOfClasses must be positive: {config.numberOfClasses}"
      ).err

    if config.maxBboxesPerClass <= 0:
      return makeError(
        HAILO_INVALID_ARGUMENT,
        &"maxBboxesPerClass must be positive: {config.maxBboxesPerClass}"
      ).err

  of hopTextDetectionDb:
    let textRes = config.textDetection.validate()
    if textRes.isErr:
      return textRes.error.err

  of hopClassificationTopK, hopTextRecognition:
    discard

  result = okVoid()

# ==============================================================================
# Constructors
# ==============================================================================

proc initRawTensorParserConfig*(
  outputNameOverride = "";
  maxRawTensorBytes = 0
): HailoOutputParserConfig =
  ## Create a parser config that copies the output tensor into RawTensorResult.
  ##
  ## maxRawTensorBytes == 0 means unlimited.  Set a positive value when probing
  ## unknown models and you want a hard safety cap.
  result = HailoOutputParserConfig(
    kind: hopRawTensor,
    outputNameOverride: outputNameOverride,
    maxRawTensorBytes: maxRawTensorBytes,
    numberOfClasses: 0,
    maxBboxesPerClass: 0,
    appScoreThreshold: 0.0'f32,
    sortDetections: false,
    textDetection: defaultTextDetectionParserConfig()
  )

proc defaultRawTensorParserConfig*(): HailoOutputParserConfig =
  result = initRawTensorParserConfig()

proc initNmsByClassParserConfig*(
  numberOfClasses: int;
  maxBboxesPerClass: int;
  appScoreThreshold = 0.25'f32;
  sortDetections = true;
  outputNameOverride = ""
): HailoOutputParserConfig =
  ## Create a parser config for HAILO_FORMAT_ORDER_HAILO_NMS_BY_CLASS output.
  result = HailoOutputParserConfig(
    kind: hopNmsByClass,
    outputNameOverride: outputNameOverride,
    maxRawTensorBytes: 0,
    numberOfClasses: numberOfClasses,
    maxBboxesPerClass: maxBboxesPerClass,
    appScoreThreshold: appScoreThreshold,
    sortDetections: sortDetections,
    textDetection: defaultTextDetectionParserConfig()
  )

proc initNmsByClassParserConfig*(
  d: Detector;
  appScoreThreshold = 0.25'f32;
  sortDetections = true;
  outputNameOverride = ""
): HE[HailoOutputParserConfig] =
  ## Build NMS parser config from Detector output metadata.
  if d.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "detector is nil").err

  if d.outputInfo.format.order != HAILO_FORMAT_ORDER_HAILO_NMS_BY_CLASS:
    return makeError(
      HAILO_INVALID_OPERATION,
      &"output format is not HAILO_FORMAT_ORDER_HAILO_NMS_BY_CLASS: got {ord(d.outputInfo.format.order)}"
    ).err

  let nmsShape = d.outputInfo.anon0.nms_shape
  result = initNmsByClassParserConfig(
    numberOfClasses = int(nmsShape.number_of_classes),
    maxBboxesPerClass = int(nmsShape.max_bboxes_per_class),
    appScoreThreshold = appScoreThreshold,
    sortDetections = sortDetections,
    outputNameOverride = outputNameOverride
  ).ok

# ==============================================================================
# Text detection parser config
# ==============================================================================

proc initTextDetectionDbParserConfig*(
  scoreThreshold = 128;
  minScore = 0.0'f32;
  minArea = 100;
  minWidth = 8;
  minHeight = 4;
  padX = 0;
  padY = 0;
  maxRegions = 0;
  eightConnected = true;
  sortBy = trsTopLeft;
  outputNameOverride = ""
): HailoOutputParserConfig =
  ## Create a parser config for UINT8 text score-map output.
  ##
  ## This first implementation uses threshold + connected components instead of
  ## a full DBPostProcess clone.  It is intended for validating the HAILO8L
  ## paddle_ocr_v5_mobile_detection output and returning YOLO-like text regions
  ## with score + axis-aligned bbox + 4-point polygon.
  result = HailoOutputParserConfig(
    kind: hopTextDetectionDb,
    outputNameOverride: outputNameOverride,
    maxRawTensorBytes: 0,
    numberOfClasses: 0,
    maxBboxesPerClass: 0,
    appScoreThreshold: 0.0'f32,
    sortDetections: false,
    textDetection: initTextDetectionParserConfig(
      scoreThreshold = scoreThreshold,
      minScore = minScore,
      minArea = minArea,
      minWidth = minWidth,
      minHeight = minHeight,
      padX = padX,
      padY = padY,
      maxRegions = maxRegions,
      eightConnected = eightConnected,
      sortBy = sortBy
    )
  )

# ==============================================================================
# Raw tensor parser
# ==============================================================================

proc parseRawTensorInto*(
  outputPtr: pointer;
  outputSize: int;
  outputMetadata: VStreamMetadata;
  dst: var HailoInferenceResult;
  requestId = 0'u64;
  userData = 0'u64;
  timing = HailoInferenceTiming();
  outputNameOverride = "";
  maxRawTensorBytes = 0;
  includeMetadataStrings = true
): HE[void] =
  ## Copy one raw output tensor into dst.raw.
  ##
  ## The copied result remains valid after the caller releases the underlying
  ## ThreadtoolsVStreamRunner output slot.
  if outputSize < 0:
    return makeError(
      HAILO_INVALID_ARGUMENT,
      &"output size must be >= 0: {outputSize}"
    ).err

  if outputSize > 0 and outputPtr.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "output buffer is nil").err

  if maxRawTensorBytes > 0 and outputSize > maxRawTensorBytes:
    return makeError(
      HAILO_INVALID_ARGUMENT,
      &"raw tensor output exceeds maxRawTensorBytes: outputSize={outputSize} maxRawTensorBytes={maxRawTensorBytes}"
    ).err

  let parseStart = getMonoTime()
  dst.resetKind(hrkRawTensor)
  dst.setCorrelation(requestId, userData)
  dst.timing = timing
  if includeMetadataStrings:
    dst.raw.outputName =
      if outputNameOverride.len > 0:
        cloneString(outputNameOverride)
      else:
        cloneString(outputMetadata.name)
    dst.raw.metadata = cloneVStreamMetadata(outputMetadata)
  else:
    ## ThreadtoolsInferenceWorker moves results across a thread queue.  Keep
    ## GC-managed metadata strings out of the reply and let the owner thread use
    ## worker.outputMetadata() when it needs display names.
    dst.raw.outputName.setLen(0)
    dst.raw.metadata = VStreamMetadata(
      name: "",
      networkName: "",
      dataType: outputMetadata.dataType,
      pixelFormat: outputMetadata.pixelFormat,
      imageType: outputMetadata.imageType,
      flags: outputMetadata.flags,
      shape: outputMetadata.shape
    )
  dst.raw.outputSize = outputSize

  let copyRes = copyRawTensorBytes(outputPtr, outputSize, dst.raw.bytes)
  if copyRes.isErr:
    dst.clear()
    return copyRes.error.err

  dst.timing.parseUs = elapsedUs(parseStart)
  result = okVoid()

# ==============================================================================
# NMS parser
# ==============================================================================

proc parseNmsByClassInto*(
  outputPtr: pointer;
  outputSize: int;
  outputMetadata: VStreamMetadata;
  config: HailoOutputParserConfig;
  dst: var HailoInferenceResult;
  requestId = 0'u64;
  userData = 0'u64;
  timing = HailoInferenceTiming()
): HE[void] =
  ## Parse HAILO_FORMAT_ORDER_HAILO_NMS_BY_CLASS output into dst.detections.
  if outputSize <= 0:
    return makeError(HAILO_INVALID_ARGUMENT, "output buffer is empty").err

  if outputPtr.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "output buffer is nil").err

  if config.kind != hopNmsByClass:
    return makeError(
      HAILO_INVALID_ARGUMENT,
      &"parser config kind is not hopNmsByClass: {config.kind}"
    ).err

  if outputMetadata.pixelFormat != pfHailoNmsByClass:
    return makeError(
      HAILO_INVALID_OPERATION,
      &"output pixel format is not HAILO_NMS_BY_CLASS: got {outputMetadata.pixelFormat}"
    ).err

  let validRes = config.validateParserConfig()
  if validRes.isErr:
    return validRes.error.err

  let parseStart = getMonoTime()
  dst.resetKind(hrkDetections)
  dst.setCorrelation(requestId, userData)
  dst.timing = timing

  let raw = cast[ptr UncheckedArray[byte]](outputPtr)
  parseNmsByClassVariableInto(
    raw.toOpenArray(0, outputSize - 1),
    config.numberOfClasses,
    config.maxBboxesPerClass,
    dst.detections.detections,
    config.appScoreThreshold
  )
  dst.timing.parseUs = elapsedUs(parseStart)

  if config.sortDetections:
    let sortStart = getMonoTime()
    detection.sortByScoreDesc(dst.detections.detections)
    dst.timing.sortUs = elapsedUs(sortStart)

  result = okVoid()

# ==============================================================================
# Text detection score-map parser
# ==============================================================================

proc parseTextDetectionDbInto*(
  outputPtr: pointer;
  outputSize: int;
  outputMetadata: VStreamMetadata;
  config: HailoOutputParserConfig;
  dst: var HailoInferenceResult;
  requestId = 0'u64;
  userData = 0'u64;
  timing = HailoInferenceTiming()
): HE[void] =
  ## Parse a UINT8 text score-map output into dst.textRegions.
  if config.kind != hopTextDetectionDb:
    return makeError(
      HAILO_INVALID_ARGUMENT,
      &"parser config kind is not hopTextDetectionDb: {config.kind}"
    ).err

  let validRes = config.validateParserConfig()
  if validRes.isErr:
    return validRes.error.err

  let parseStart = getMonoTime()
  dst.resetKind(hrkTextRegions)
  dst.setCorrelation(requestId, userData)
  dst.timing = timing

  let parseRes = parseTextDetectionScoreMapInto(
    outputPtr,
    outputSize,
    outputMetadata,
    config.textDetection,
    dst.textRegions
  )
  if parseRes.isErr:
    dst.clear()
    return parseRes.error.err

  dst.timing.parseUs = elapsedUs(parseStart)
  result = okVoid()

# ==============================================================================
# Generic parser entry points
# ==============================================================================

proc parseOutputInto*(
  config: HailoOutputParserConfig;
  outputPtr: pointer;
  outputSize: int;
  outputMetadata: VStreamMetadata;
  dst: var HailoInferenceResult;
  requestId = 0'u64;
  userData = 0'u64;
  timing = HailoInferenceTiming();
  includeMetadataStrings = true
): HE[void] =
  ## Parse a single HAILO output buffer according to config.
  ##
  ## This does not release any vstream slot.  Caller owns slot lifetime.
  let validRes = config.validateParserConfig()
  if validRes.isErr:
    return validRes.error.err

  case config.kind
  of hopRawTensor:
    result = parseRawTensorInto(
      outputPtr,
      outputSize,
      outputMetadata,
      dst,
      requestId = requestId,
      userData = userData,
      timing = timing,
      outputNameOverride = config.effectiveOutputName(outputMetadata),
      maxRawTensorBytes = config.maxRawTensorBytes,
      includeMetadataStrings = includeMetadataStrings
    )

  of hopNmsByClass:
    result = parseNmsByClassInto(
      outputPtr,
      outputSize,
      outputMetadata,
      config,
      dst,
      requestId = requestId,
      userData = userData,
      timing = timing
    )

  of hopTextDetectionDb:
    result = parseTextDetectionDbInto(
      outputPtr,
      outputSize,
      outputMetadata,
      config,
      dst,
      requestId = requestId,
      userData = userData,
      timing = timing
    )

  of hopClassificationTopK, hopTextRecognition:
    result = makeError(
      HAILO_NOT_SUPPORTED,
      &"parser kind is not implemented yet: {config.kind}"
    ).err
