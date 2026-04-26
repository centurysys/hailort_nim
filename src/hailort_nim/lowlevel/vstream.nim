import std/strutils
import ./network_group
import ./common/vstream_types
import ../bindings/[c_api, types]
import ../internal/[error, helper]

# ==============================================================================
# Public type aliases
# ==============================================================================
type
  InputVStreamObj* = object
    raw*: hailo_input_vstream
  InputVStream* = ref InputVStreamObj
  OutputVStreamObj* = object
    raw*: hailo_output_vstream
  OutputVStream* = ref OutputVStreamObj
  InputVStreamsObj* = object
    raws*: seq[hailo_input_vstream]
  InputVStreams* = ref InputVStreamsObj
  OutputVStreamsObj* = object
    raws*: seq[hailo_output_vstream]
  OutputVStreams* = ref OutputVStreamsObj

# ==============================================================================
# Name / info helpers
# ==============================================================================

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc name*(info: VstreamInfo): string =
  cCharArrayToString(info.name)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc networkName*(info: VstreamInfo): string =
  cCharArrayToString(info.network_name)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc name*(param: InputVstreamParamsByName): string =
  cCharArrayToString(param.name)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc name*(param: OutputVstreamParamsByName): string =
  cCharArrayToString(param.name)

# ==============================================================================
# Format / shape helpers
# ==============================================================================

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc tensorDataType*(fmt: Format): TensorDataType =
  result = case fmt.type_field
    of HAILO_FORMAT_TYPE_AUTO:
      tdtAuto
    of HAILO_FORMAT_TYPE_UINT8:
      tdtUint8
    of HAILO_FORMAT_TYPE_UINT16:
      tdtUint16
    of HAILO_FORMAT_TYPE_FLOAT32:
      tdtFloat32
    else:
      tdtUnknown

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc pixelFormat*(fmt: Format): PixelFormat =
  result = case fmt.order
    of HAILO_FORMAT_ORDER_AUTO:
      pfAuto
    of HAILO_FORMAT_ORDER_NHWC:
      pfNhwc
    of HAILO_FORMAT_ORDER_NHCW:
      pfNhcw
    of HAILO_FORMAT_ORDER_NCHW:
      pfNchw
    of HAILO_FORMAT_ORDER_NHW:
      pfNhw
    of HAILO_FORMAT_ORDER_NC:
      pfNc
    of HAILO_FORMAT_ORDER_RGB888:
      pfRgb888
    of HAILO_FORMAT_ORDER_RGB4:
      pfRgb4
    of HAILO_FORMAT_ORDER_NV12:
      pfNv12
    of HAILO_FORMAT_ORDER_NV21:
      pfNv21
    of HAILO_FORMAT_ORDER_YUY2:
      pfYuy2
    of HAILO_FORMAT_ORDER_I420:
      pfI420
    of HAILO_FORMAT_ORDER_FCR:
      pfFcr
    of HAILO_FORMAT_ORDER_F8CR:
      pfF8cr
    of HAILO_FORMAT_ORDER_BAYER_RGB:
      pfBayerRgb
    of HAILO_FORMAT_ORDER_12_BIT_BAYER_RGB:
      pf12BitBayerRgb
    of HAILO_FORMAT_ORDER_HAILO_NMS:
      pfHailoNms
    of HAILO_FORMAT_ORDER_HAILO_NMS_WITH_BYTE_MASK:
      pfHailoNmsWithByteMask
    of HAILO_FORMAT_ORDER_HAILO_NMS_ON_CHIP:
      pfHailoNmsOnChip
    of HAILO_FORMAT_ORDER_HAILO_NMS_BY_CLASS:
      pfHailoNmsByClass
    of HAILO_FORMAT_ORDER_HAILO_NMS_BY_SCORE:
      pfHailoNmsByScore
    of HAILO_FORMAT_ORDER_HAILO_YYUV:
      pfHailoYyuv
    of HAILO_FORMAT_ORDER_HAILO_YYVU:
      pfHailoYyvu
    of HAILO_FORMAT_ORDER_HAILO_YYYYUV:
      pfHailoYyyyuv
    else:
      pfUnknown

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc dataTypeName*(kind: TensorDataType): string =
  result = case kind
    of tdtAuto:
      "AUTO"
    of tdtUint8:
      "UINT8"
    of tdtUint16:
      "UINT16"
    of tdtFloat32:
      "FLOAT32"
    else:
      "UNKNOWN"

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc pixelFormatName*(fmt: PixelFormat): string =
  result = case fmt
    of pfAuto:
      "AUTO"
    of pfNhwc:
      "NHWC"
    of pfNhcw:
      "NHCW"
    of pfNchw:
      "NCHW"
    of pfNhw:
      "NHW"
    of pfNc:
      "NC"
    of pfRgb888:
      "RGB888"
    of pfRgb4:
      "RGB4"
    of pfNv12:
      "NV12"
    of pfNv21:
      "NV21"
    of pfYuy2:
      "YUY2"
    of pfI420:
      "I420"
    of pfFcr:
      "FCR"
    of pfF8cr:
      "F8CR"
    of pfBayerRgb:
      "BAYER_RGB"
    of pf12BitBayerRgb:
      "12_BIT_BAYER_RGB"
    of pfHailoNms:
      "HAILO_NMS"
    of pfHailoNmsWithByteMask:
      "HAILO_NMS_WITH_BYTE_MASK"
    of pfHailoNmsOnChip:
      "HAILO_NMS_ON_CHIP"
    of pfHailoNmsByClass:
      "HAILO_NMS_BY_CLASS"
    of pfHailoNmsByScore:
      "HAILO_NMS_BY_SCORE"
    of pfHailoYyuv:
      "HAILO_YYUV"
    of pfHailoYyvu:
      "HAILO_YYVU"
    of pfHailoYyyyuv:
      "HAILO_YYYYUV"
    else:
      "UNKNOWN"

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc formatFlags*(fmt: Format): set[FormatFlag] =
  let rawFlags = cint(fmt.flags)
  var resultFlags: set[FormatFlag] = {}

  if (rawFlags and cint(HAILO_FORMAT_FLAGS_QUANTIZED)) != 0:
    resultFlags.incl ffQuantized

  if (rawFlags and cint(HAILO_FORMAT_FLAGS_TRANSPOSED)) != 0:
    resultFlags.incl ffTransposed

  result = resultFlags

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc `$`*(flags: set[FormatFlag]): string =
  if flags.len == 0:
    return "NONE"
  var parts: seq[string] = @[]
  if ffQuantized in flags:
    parts.add("QUANTIZED")
  if ffTransposed in flags:
    parts.add("TRANSPOSED")

  result = parts.join("|")

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc imageShape*(info: VstreamInfo): ImageShape =
  result = ImageShape(
    height: int(info.anon0.shape.height),
    width: int(info.anon0.shape.width),
    channels: int(info.anon0.shape.features)
  )

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc `$`*(shape: ImageShape): string =
  result = $shape.height & " x " & $shape.width & " x " & $shape.channels

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc imageType*(info: VstreamInfo): ImageType =
  let pf = pixelFormat(info.format)
  let shape = imageShape(info)

  result = case pf
    of pfNhwc:
      case shape.channels
      of 3:
        itNhwc3
      of 4:
        itNhwc4
      else:
        itUnknown
    of pfNv12:
      itNv12
    of pfNv21:
      itNv21
    of pfYuy2:
      itYuy2
    of pfI420:
      itI420
    else:
      itUnknown

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc metadata*(info: VstreamInfo): VStreamMetadata =
  result = VStreamMetadata(
    name: info.name(),
    networkName: info.networkName(),
    dataType: tensorDataType(info.format),
    pixelFormat: pixelFormat(info.format),
    imageType: imageType(info),
    flags: formatFlags(info.format),
    shape: imageShape(info)
  )

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc isNhwc*(info: VstreamInfo): bool =
  result = pixelFormat(info.format) == pfNhwc

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc isNhwc3Input*(info: VstreamInfo): bool =
  let meta = info.metadata
  result = meta.dataType == tdtUint8 and meta.pixelFormat == pfNhwc and
      meta.shape.channels == 3

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc isNhwc4Input*(info: VstreamInfo): bool =
  let meta = info.metadata
  result = meta.dataType == tdtUint8 and meta.pixelFormat == pfNhwc and
      meta.shape.channels == 4

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc expectedByteSize*(info: VstreamInfo): HE[int] =
  let shape = imageShape(info)
  let h = shape.height
  let w = shape.width
  let c = shape.channels

  if h <= 0 or w <= 0 or c <= 0:
    return makeError(HAILO_INVALID_ARGUMENT,
      "invalid vstream shape").err

  result = case pixelFormat(info.format)
    of pfNv12, pfNv21:
      ok((w * h * 3) div 2)
    of pfI420:
      ok((w * h * 3) div 2)
    of pfYuy2:
      ok(w * h * 2)
    else:
      ok(w * h * c)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc validateInputBuffer*(info: VstreamInfo, dataLen: int): HE[void] =
  if dataLen <= 0:
    return makeError(HAILO_INVALID_ARGUMENT, "input buffer is empty").err

  let expectedRes = info.expectedByteSize()
  if expectedRes.isErr:
    return expectedRes.error.err

  let expected = expectedRes.get
  if dataLen != expected:
    let shape = info.imageShape
    let msg = "input buffer size mismatch: expected=" & $expected &
        " actual=" & $dataLen & " shape=" & $shape
    return makeError(HAILO_INVALID_ARGUMENT, msg).err

  result = okVoid()

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc validateNhwc4Input*(info: VstreamInfo, dataLen: int): HE[void] =
  let meta = info.metadata
  if meta.dataType != tdtUint8:
    return makeError(HAILO_INVALID_ARGUMENT,
        "input data type is not UINT8: " & dataTypeName(meta.dataType)).err
  if meta.pixelFormat != pfNhwc:
    return makeError(HAILO_INVALID_ARGUMENT,
        "input pixel format is not NHWC: " & pixelFormatName(meta.pixelFormat)).err
  if meta.shape.channels != 4:
    return makeError(HAILO_INVALID_ARGUMENT,
        "input channels is not 4: " & $meta.shape.channels).err

  result = info.validateInputBuffer(dataLen)

# ==============================================================================
# Raw handles
# ==============================================================================

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc rawHandle*(s: InputVStream): hailo_input_vstream {.inline.} =
  if s.isNil: nil else: s.raw

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc rawHandle*(s: OutputVStream): hailo_output_vstream {.inline.} =
  if s.isNil: nil else: s.raw

# ==============================================================================
# Create / destroy groups
# ==============================================================================

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc createInputVstreams*(ng: NetworkGroup, params: openArray[InputVstreamParamsByName]):
    HE[InputVStreams] =
  if ng.isNil or ng.rawHandle.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "network group is nil").err
  if params.len == 0:
    return InputVStreams(raws: @[]).ok
  var localParams = @params
  var raws = newSeq[hailo_input_vstream](localParams.len)
  let res = hailo_create_input_vstreams(ng.rawHandle, localParams[0].addr,
      csize_t(localParams.len), raws[0].addr)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  result = InputVStreams(raws: raws).ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc createOutputVstreams*(ng: NetworkGroup, params: openArray[OutputVstreamParamsByName]):
    HE[OutputVStreams] =
  if ng.isNil or ng.rawHandle.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "network group is nil").err
  if params.len == 0:
    return OutputVStreams(raws: @[]).ok
  var localParams = @params
  var raws = newSeq[hailo_output_vstream](localParams.len)
  let res = hailo_create_output_vstreams(ng.rawHandle, localParams[0].addr,
      csize_t(localParams.len), raws[0].addr)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  result = OutputVStreams(raws: raws).ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc close*(streams: InputVStreams): HE[void] =
  if streams.isNil or streams.raws.len == 0:
    return okVoid()
  let res = hailo_release_input_vstreams(streams.raws[0].addr, csize_t(streams.raws.len))
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  streams.raws.setLen(0)
  okVoid()

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc close*(streams: OutputVStreams): HE[void] =
  if streams.isNil or streams.raws.len == 0:
    return okVoid()
  let res = hailo_release_output_vstreams(streams.raws[0].addr, csize_t(streams.raws.len))
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  streams.raws.setLen(0)
  okVoid()

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc clear*(streams: InputVStreams): HE[void] =
  if streams.isNil or streams.raws.len == 0:
    return okVoid()
  check(hailo_clear_input_vstreams(streams.raws[0].addr, csize_t(streams.raws.len)))

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc clear*(streams: OutputVStreams): HE[void] =
  if streams.isNil or streams.raws.len == 0:
    return okVoid()
  check(hailo_clear_output_vstreams(streams.raws[0].addr, csize_t(streams.raws.len)))

# ==============================================================================
# Collection helpers
# ==============================================================================

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc len*(streams: InputVStreams): int {.inline.} =
  if streams.isNil: 0 else: streams.raws.len

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc len*(streams: OutputVStreams): int {.inline.} =
  if streams.isNil: 0 else: streams.raws.len

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc `[]`*(streams: InputVStreams, i: int): InputVStream =
  InputVStream(raw: streams.raws[i])

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc `[]`*(streams: OutputVStreams, i: int): OutputVStream =
  OutputVStream(raw: streams.raws[i])

# ==============================================================================
# Input vstream info / io
# ==============================================================================

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc frameSize*(s: InputVStream): HE[int] =
  if s.isNil or s.raw.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "input vstream is nil").err
  var sz: csize_t
  let res = hailo_get_input_vstream_frame_size(s.raw, addr sz)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  result = int(sz).ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc info*(s: InputVStream): HE[VstreamInfo] =
  if s.isNil or s.raw.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "input vstream is nil").err
  var info: VstreamInfo
  let res = hailo_get_input_vstream_info(s.raw, addr info)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  result = info.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc metadata*(s: InputVStream): HE[VStreamMetadata] =
  let infoRes = s.info()
  if infoRes.isErr:
    return infoRes.error.err
  result = infoRes.get.metadata.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc userBufferFormat*(s: InputVStream): HE[Format] =
  if s.isNil or s.raw.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "input vstream is nil").err
  var fmt: Format
  let res = hailo_get_input_vstream_user_format(s.raw, addr fmt)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  result = fmt.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc quantInfos*(s: InputVStream): HE[seq[QuantInfo]] =
  if s.isNil or s.raw.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "input vstream is nil").err
  var count: csize_t = 8
  while true:
    var infos = newSeq[QuantInfo](int(count))
    var actualCount = count
    let res = hailo_get_input_vstream_quant_infos(s.raw, infos[0].addr,
        addr actualCount)
    if res == HAILO_INSUFFICIENT_BUFFER:
      count = actualCount
      continue
    if res != HAILO_SUCCESS:
      return makeError(res, $res).err
    infos.setLen(int(actualCount))
    return infos.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc name*(s: InputVStream): HE[string] =
  let infoRes = s.info()
  if infoRes.isErr:
    return infoRes.error.err
  result = infoRes.get.name().ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc networkName*(s: InputVStream): HE[string] =
  let infoRes = s.info()
  if infoRes.isErr:
    return infoRes.error.err
  result = infoRes.get.networkName().ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc write*(s: InputVStream, buffer: pointer, size: Natural): HE[void] =
  if s.isNil or s.raw.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "input vstream is nil").err
  check(hailo_vstream_write_raw_buffer(s.raw, buffer, csize_t(size)))

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc write*(s: InputVStream, data: openArray[byte]): HE[void] =
  if data.len == 0:
    return makeError(HAILO_INVALID_ARGUMENT, "input buffer is empty").err
  result = s.write(unsafeAddr data[0], data.len)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc write*(s: InputVStream, buffer: PixBuffer): HE[void] =
  if s.isNil or s.raw.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "input vstream is nil").err
  let b = buffer
  check(hailo_vstream_write_pix_buffer(s.raw, addr b))


# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc writeNhwc4*(s: InputVStream, data: openArray[byte]): HE[void] =
  if s.isNil or s.raw.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "input vstream is nil").err
  if data.len == 0:
    return makeError(HAILO_INVALID_ARGUMENT, "input buffer is empty").err

  let infoRes = s.info()
  if infoRes.isErr:
    return infoRes.error.err

  let validateRes = infoRes.get.validateNhwc4Input(data.len)
  if validateRes.isErr:
    return validateRes.error.err

  result = s.write(data)
# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc flush*(s: InputVStream): HE[void] =
  if s.isNil or s.raw.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "input vstream is nil").err
  check(hailo_flush_input_vstream(s.raw))

# ==============================================================================
# Output vstream info / io
# ==============================================================================

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc frameSize*(s: OutputVStream): HE[int] =
  if s.isNil or s.raw.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "output vstream is nil").err
  var sz: csize_t
  let res = hailo_get_output_vstream_frame_size(s.raw, addr sz)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  result = int(sz).ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc info*(s: OutputVStream): HE[VstreamInfo] =
  if s.isNil or s.raw.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "output vstream is nil").err
  var info: VstreamInfo
  let res = hailo_get_output_vstream_info(s.raw, addr info)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  result = info.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc metadata*(s: OutputVStream): HE[VStreamMetadata] =
  let infoRes = s.info()
  if infoRes.isErr:
    return infoRes.error.err
  result = infoRes.get.metadata.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc userBufferFormat*(s: OutputVStream): HE[Format] =
  if s.isNil or s.raw.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "output vstream is nil").err
  var fmt: Format
  let res = hailo_get_output_vstream_user_format(s.raw, addr fmt)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  result = fmt.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc quantInfos*(s: OutputVStream): HE[seq[QuantInfo]] =
  if s.isNil or s.raw.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "output vstream is nil").err
  var count: csize_t = 8
  while true:
    var infos = newSeq[QuantInfo](int(count))
    var actualCount = count
    let res = hailo_get_output_vstream_quant_infos(s.raw, infos[0].addr,
        addr actualCount)
    if res == HAILO_INSUFFICIENT_BUFFER:
      count = actualCount
      continue
    if res != HAILO_SUCCESS:
      return makeError(res, $res).err
    infos.setLen(int(actualCount))
    return infos.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc name*(s: OutputVStream): HE[string] =
  let infoRes = s.info()
  if infoRes.isErr:
    return infoRes.error.err
  result = infoRes.get.name().ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc networkName*(s: OutputVStream): HE[string] =
  let infoRes = s.info()
  if infoRes.isErr:
    return infoRes.error.err
  result = infoRes.get.networkName().ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc read*(s: OutputVStream, buffer: pointer, size: Natural): HE[void] =
  if s.isNil or s.raw.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "output vstream is nil").err
  check(hailo_vstream_read_raw_buffer(s.raw, buffer, csize_t(size)))

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc read*(s: OutputVStream, size: Natural): HE[seq[byte]] =
  if size == 0:
    return makeError(HAILO_INVALID_ARGUMENT, "output size is zero").err
  var data = newSeq[byte](size)
  let readRes = s.read(addr data[0], size)
  if readRes.isErr:
    return readRes.error.err
  result = data.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc setNmsScoreThreshold*(s: OutputVStream, threshold: float32): HE[void] =
  if s.isNil or s.raw.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "output vstream is nil").err
  check(hailo_vstream_set_nms_score_threshold(s.raw, threshold))

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc setNmsIouThreshold*(s: OutputVStream, threshold: float32): HE[void] =
  if s.isNil or s.raw.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "output vstream is nil").err
  check(hailo_vstream_set_nms_iou_threshold(s.raw, threshold))

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc setNmsMaxProposalsPerClass*(s: OutputVStream, maxProposalsPerClass: uint32):
    HE[void] =
  if s.isNil or s.raw.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "output vstream is nil").err
  check(hailo_vstream_set_nms_max_proposals_per_class(s.raw, maxProposalsPerClass))

# ==============================================================================
# Static helpers
# ==============================================================================

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc frameSize*(info: VstreamInfo, fmt: Format): HE[int] =
  var infoCopy = info
  var fmtCopy = fmt
  var sz: csize_t
  let res = hailo_get_vstream_frame_size(addr infoCopy, addr fmtCopy, addr sz)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  result = int(sz).ok

# ==============================================================================
# Test
# ==============================================================================

when isMainModule:
  import std/os
  import ./hef
  import ./vdevice

  proc printInputSummary(index: int, s: InputVStream) =
    let metaRes = s.metadata()
    let sizeRes = s.frameSize()
    let userFmtRes = s.userBufferFormat()

    if metaRes.isErr:
      echo "  input[", index, "]: error: ", metaRes.error
      return

    let meta = metaRes.get
    echo "  input[", index, "]:"
    echo "    name        : ", meta.name
    echo "    network     : ", meta.networkName
    echo "    type        : ", dataTypeName(meta.dataType)
    echo "    order       : ", pixelFormatName(meta.pixelFormat)
    echo "    image_type  : ", $meta.imageType
    echo "    flags       : ", $meta.flags
    echo "    shape       : ", $meta.shape

    if sizeRes.isOk:
      echo "    frame_size  : ", sizeRes.get

    if userFmtRes.isOk:
      let userFmt = userFmtRes.get
      echo "    user_format : order=", pixelFormatName(pixelFormat(userFmt)),
          " type=", dataTypeName(tensorDataType(userFmt)),
          " flags=", $formatFlags(userFmt)

  proc printOutputSummary(index: int, s: OutputVStream) =
    let metaRes = s.metadata()
    let sizeRes = s.frameSize()
    let userFmtRes = s.userBufferFormat()

    if metaRes.isErr:
      echo "  output[", index, "]: error: ", metaRes.error
      return

    let meta = metaRes.get
    echo "  output[", index, "]:"
    echo "    name        : ", meta.name
    echo "    network     : ", meta.networkName
    echo "    type        : ", dataTypeName(meta.dataType)
    echo "    order       : ", pixelFormatName(meta.pixelFormat)
    echo "    flags       : ", $meta.flags
    echo "    shape       : ", $meta.shape

    if sizeRes.isOk:
      echo "    frame_size  : ", sizeRes.get

    if userFmtRes.isOk:
      let userFmt = userFmtRes.get
      echo "    user_format : order=", pixelFormatName(pixelFormat(userFmt)),
          " type=", dataTypeName(tensorDataType(userFmt)),
          " flags=", $formatFlags(userFmt)

  if paramCount() < 1:
    echo "Usage: vstream <model.hef>"
    quit 1

  let hefPath = paramStr(1)
  echo "Opening HEF: ", hefPath
  let hefRes = openHef(hefPath)
  if hefRes.isErr:
    echo "Error: ", hefRes.error
    quit 1
  let hefObj = hefRes.get
  echo "HEF opened"

  let vdevRes = createVdevice()
  if vdevRes.isErr:
    echo "Error: ", vdevRes.error
    discard hefObj.close()
    quit 1
  let vdevObj = vdevRes.get
  echo "VDevice created"

  let ngRes = configureOne(vdevObj, hefObj)
  if ngRes.isErr:
    echo "Error: ", ngRes.error
    discard vdevObj.close()
    discard hefObj.close()
    quit 1
  let ngObj = ngRes.get
  echo "Network group configured"

  let inParamsRes = makeInputVstreamParams(ngObj)
  if inParamsRes.isErr:
    echo "Error: ", inParamsRes.error
    discard ngObj.close()
    discard vdevObj.close()
    discard hefObj.close()
    quit 1
  let inputParams = inParamsRes.get
  echo "Input vstream params: ", inputParams.len

  let outParamsRes = makeOutputVstreamParams(ngObj)
  if outParamsRes.isErr:
    echo "Error: ", outParamsRes.error
    discard ngObj.close()
    discard vdevObj.close()
    discard hefObj.close()
    quit 1
  let outputParams = outParamsRes.get
  echo "Output vstream params: ", outputParams.len

  let inStreamsRes = createInputVstreams(ngObj, inputParams)
  if inStreamsRes.isErr:
    echo "Error: ", inStreamsRes.error
    discard ngObj.close()
    discard vdevObj.close()
    discard hefObj.close()
    quit 1
  let inStreams = inStreamsRes.get
  echo "Input vstreams: ", inStreams.len

  let outStreamsRes = createOutputVstreams(ngObj, outputParams)
  if outStreamsRes.isErr:
    echo "Error: ", outStreamsRes.error
    discard inStreams.close()
    discard ngObj.close()
    discard vdevObj.close()
    discard hefObj.close()
    quit 1
  let outStreams = outStreamsRes.get
  echo "Output vstreams: ", outStreams.len

  for i in 0..<inStreams.len:
    printInputSummary(i, inStreams[i])

  for i in 0..<outStreams.len:
    printOutputSummary(i, outStreams[i])

  discard outStreams.close()
  discard inStreams.close()
  discard ngObj.close()
  discard vdevObj.close()
  discard hefObj.close()
