import ../lowlevel
import ../models/detection

# ==============================================================================
# Generic inference result model
# ==============================================================================

type
  HailoResultKind* = enum
    ## Logical result kind produced by a HAILO output parser.
    ##
    ## hrkNone is useful for zero-initialized values and for reusing a reply
    ## object after clear().  The other values represent parser-specific payloads
    ## carried by HailoInferenceResult.
    hrkNone
    hrkDetections
    hrkClassification
    hrkTextRegions
    hrkTextRecognition
    hrkRawTensor

  HailoInferenceTiming* = object
    ## Per-request timing metadata shared by detector-specific and generic
    ## inference paths.
    ##
    ## Values are microseconds.  totalUs is intentionally optional; some callers
    ## only have per-stage timings at the layer where this object is filled.
    slotIndex*: int
    writeUs*: int64
    readUs*: int64
    parseUs*: int64
    sortUs*: int64
    totalUs*: int64

  DetectionResult* = object
    ## Parsed object-detection result.
    ##
    ## This wraps the existing seq[Detection] so generic code can carry
    ## detections without depending on ThreadtoolsDetectorWorkerResult.
    detections*: seq[Detection]

  ClassScore* = object
    ## One classification score.
    classId*: int
    score*: float32

  ClassificationResult* = object
    ## Top-K classification result.
    scores*: seq[ClassScore]

  PointF32* = object
    ## Floating-point image coordinate.
    x*: float32
    y*: float32

  RectF32* = object
    ## Axis-aligned rectangle in model/application coordinate space.
    x*: float32
    y*: float32
    width*: float32
    height*: float32

  TextRegion* = object
    ## One detected text region.
    ##
    ## points carries a 4-point polygon in clockwise order, while bbox is the
    ## corresponding axis-aligned rectangle.  Keep points as a fixed array so
    ## text-region replies moved through ThreadQueue do not contain nested seqs.
    ## The coordinate restore step remains an application/codecpipe
    ## responsibility because it needs original image size and preprocessing
    ## metadata.
    score*: float32
    area*: int
    points*: array[4, PointF32]
    bbox*: RectF32

  TextRegionResult* = object
    ## Text detection result.
    regions*: seq[TextRegion]

  RecognizedChar* = object
    ## Optional per-character OCR confidence item.
    text*: string
    confidence*: float32

  TextRecognitionResult* = object
    ## Text recognition result for one crop or sequence.
    text*: string
    confidence*: float32
    chars*: seq[RecognizedChar]

  RawTensorBytes* = object
    ## Raw tensor byte storage that can safely move through ThreadQueue.
    ##
    ## Using a GC-managed seq[byte] here made teardown fragile when large raw
    ## tensors were moved across thread/channel boundaries.  This buffer owns
    ## shared memory explicitly and frees it in a no-raise destructor.
    data*: pointer
    size*: int

  RawTensorResult* = object
    ## Raw output tensor copied out of a ThreadtoolsVStreamRunner slot.
    ##
    ## The copied bytes live in RawTensorBytes, so callers can inspect non-YOLO
    ## model output after the vstream slot is released without relying on seq
    ## ownership crossing the worker reply queue.
    outputName*: string
    outputSize*: int
    metadata*: VStreamMetadata
    bytes*: RawTensorBytes

  HailoInferenceResult* = object
    ## Generic parser result wrapper.
    ##
    ## This is deliberately a normal object instead of an object variant for now:
    ## it is simple to move through ThreadQueue, easy to clear/reuse, and avoids
    ## making the early parser work depend on a closed inheritance/variant design.
    ## Hot-path APIs should still prefer out-var style, for example
    ## waitReply(reply: var X): HE[void], rather than returning
    ## HE[HailoInferenceResult].
    kind*: HailoResultKind
    requestId*: uint64
    userData*: uint64
    timing*: HailoInferenceTiming
    detections*: DetectionResult
    classification*: ClassificationResult
    textRegions*: TextRegionResult
    text*: TextRecognitionResult
    raw*: RawTensorResult


# ==============================================================================
# Lifetime hooks
# ==============================================================================

proc `=copy`*(dest: var RawTensorBytes, src: RawTensorBytes)
    {.error: "RawTensorBytes cannot be copied; use move or copyRawTensorBytes".}

proc `=destroy`*(b: var RawTensorBytes) {.raises: [].} =
  if not b.data.isNil:
    deallocShared(b.data)
  b.data = nil
  b.size = 0

proc `=wasMoved`*(b: var RawTensorBytes) {.raises: [].} =
  ## Put a moved-from RawTensorBytes into an inert state.
  ##
  ## RawTensorBytes owns a manually allocated pointer.  Make the moved-from state
  ## explicit so queue/channel moves cannot leave two objects that both try to
  ## free the same buffer at scope exit.
  b.data = nil
  b.size = 0

proc `=sink`*(dest: var RawTensorBytes; src: RawTensorBytes) {.raises: [].} =
  ## Move assignment for RawTensorBytes.
  ##
  ## The compiler can generate a default sink hook, but this type is the one raw
  ## pointer owner in HailoInferenceResult, so keep the transfer rule explicit.
  if dest.data != src.data:
    `=destroy`(dest)
    `=wasMoved`(dest)

  dest.data = src.data
  dest.size = src.size

# ==============================================================================
# Deep-copy helpers
# ==============================================================================

proc cloneString*(s: string): string =
  ## Return a physically independent string.
  ##
  ## This is intentionally used for values that are moved through ThreadQueue.
  ## Plain string assignment may share the same ref-counted string buffer, which
  ## is not a good fit for cross-thread ownership transfer.
  result = newString(s.len)
  if s.len > 0:
    copyMem(addr result[0], unsafeAddr s[0], s.len)

proc cloneVStreamMetadata*(m: VStreamMetadata): VStreamMetadata =
  ## Deep-copy string fields of VStreamMetadata.
  ##
  ## The enum/set/shape fields are value fields; name/networkName must be cloned
  ## when the metadata is embedded in a reply moved from a worker thread to the
  ## caller thread.
  result.name = cloneString(m.name)
  result.networkName = cloneString(m.networkName)
  result.dataType = m.dataType
  result.pixelFormat = m.pixelFormat
  result.imageType = m.imageType
  result.flags = m.flags
  result.shape = m.shape

# ==============================================================================
# Constructors
# ==============================================================================

proc initDetectionResult*(detections: sink seq[Detection]): DetectionResult =
  result.detections = move detections

proc initClassificationResult*(scores: sink seq[ClassScore]): ClassificationResult =
  result.scores = move scores

proc initTextRegionResult*(regions: sink seq[TextRegion]): TextRegionResult =
  result.regions = move regions

proc initTextRecognitionResult*(
  text: string;
  confidence: float32;
  chars: sink seq[RecognizedChar]
): TextRecognitionResult =
  result.text = text
  result.confidence = confidence
  result.chars = move chars

proc initRawTensorResult*(
  outputName: string;
  outputSize: int;
  metadata: VStreamMetadata;
  bytes: sink RawTensorBytes
): RawTensorResult =
  result.outputName = cloneString(outputName)
  result.outputSize = outputSize
  result.metadata = cloneVStreamMetadata(metadata)
  result.bytes = move bytes

# ==============================================================================
# Reuse helpers
# ==============================================================================

proc clear*(r: var HailoInferenceTiming) =
  r = HailoInferenceTiming(slotIndex: -1)

proc clear*(r: var DetectionResult) =
  r.detections.setLen(0)

proc clear*(r: var ClassificationResult) =
  r.scores.setLen(0)

proc clear*(r: var TextRegionResult) =
  r.regions.setLen(0)

proc clear*(r: var TextRecognitionResult) =
  r.text.setLen(0)
  r.confidence = 0.0'f32
  r.chars.setLen(0)

proc clear*(r: var RawTensorResult) =
  r.outputName.setLen(0)
  r.outputSize = 0
  r.metadata = VStreamMetadata()
  `=destroy`(r.bytes)

proc clear*(r: var HailoInferenceResult) =
  ## Reset logical contents while keeping seq capacities where possible.
  r.kind = hrkNone
  r.requestId = 0'u64
  r.userData = 0'u64
  r.timing.clear()
  r.detections.clear()
  r.classification.clear()
  r.textRegions.clear()
  r.text.clear()
  r.raw.clear()

proc resetKind*(r: var HailoInferenceResult; kind: HailoResultKind) =
  ## Clear previous payload and set the new logical result kind.
  r.clear()
  r.kind = kind

proc setCorrelation*(
  r: var HailoInferenceResult;
  requestId: uint64;
  userData: uint64
) =
  r.requestId = requestId
  r.userData = userData

# ==============================================================================
# Raw tensor byte helpers
# ==============================================================================

proc len*(b: var RawTensorBytes): int {.inline.} =
  result = b.size

proc isEmpty*(b: var RawTensorBytes): bool {.inline.} =
  result = b.size <= 0

proc copyRawTensorBytes*(src: pointer; size: int; dst: var RawTensorBytes): HE[void] =
  ## Replace dst with a shared-memory copy of src[0 ..< size].
  if size < 0:
    return makeError(HAILO_INVALID_ARGUMENT, "raw tensor byte size must be >= 0").err

  if size > 0 and src.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "raw tensor source pointer is nil").err

  `=destroy`(dst)

  if size == 0:
    return okVoid()

  let p = allocShared0(size)
  if p.isNil:
    return makeError(HAILO_OUT_OF_HOST_MEMORY, "failed to allocate raw tensor byte buffer").err

  copyMem(p, src, size)
  dst.data = p
  dst.size = size
  result = okVoid()

proc copyToSeq*(b: var RawTensorBytes): seq[byte] =
  ## Return a normal seq copy for code that needs seq semantics.
  result = newSeq[byte](max(0, b.size))
  if b.size > 0 and not b.data.isNil:
    copyMem(addr result[0], b.data, b.size)

proc byteAt*(b: var RawTensorBytes; index: int): byte =
  if index < 0 or index >= b.size or b.data.isNil:
    raise newException(IndexDefect, "RawTensorBytes index out of bounds")

  let p = cast[ptr UncheckedArray[byte]](b.data)
  result = p[index]

# ==============================================================================
# Text region compatibility helpers
# ==============================================================================

proc toDetection*(
  region: TextRegion;
  imageWidth: int;
  imageHeight: int;
  classId = 0
): Detection =
  ## Convert one TextRegion into the existing normalized Detection shape.
  ##
  ## Text detection is class-agnostic, so classId defaults to 0.  The returned
  ## box uses the same normalized xMin/yMin/xMax/yMax convention as YOLO/NMS
  ## detections in hailort_nim/models/detection.nim.
  let w = max(1, imageWidth)
  let h = max(1, imageHeight)
  result.classId = classId
  result.score = region.score
  result.xMin = region.bbox.x / float32(w)
  result.yMin = region.bbox.y / float32(h)
  result.xMax = (region.bbox.x + region.bbox.width) / float32(w)
  result.yMax = (region.bbox.y + region.bbox.height) / float32(h)
  result = result.clamped()

proc toDetections*(
  regions: openArray[TextRegion];
  imageWidth: int;
  imageHeight: int;
  classId = 0
): seq[Detection] =
  ## Convert text regions into YOLO-like normalized Detection records.
  result = newSeqOfCap[Detection](regions.len)
  for region in regions:
    result.add(region.toDetection(imageWidth, imageHeight, classId))
