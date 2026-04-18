import ./network_group
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
  result = infoRes.get.name.cCharArrayToString.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc networkName*(s: InputVStream): HE[string] =
  let infoRes = s.info()
  if infoRes.isErr:
    return infoRes.error.err
  result = infoRes.get.networkName.cCharArrayToString.ok

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
  result = infoRes.get.name.cCharArrayToString.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc networkName*(s: OutputVStream): HE[string] =
  let infoRes = s.info()
  if infoRes.isErr:
    return infoRes.error.err
  result = infoRes.get.networkName.cCharArrayToString.ok

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
    let s = inStreams[i]
    let nameRes = s.name()
    let sizeRes = s.frameSize()
    if nameRes.isOk and sizeRes.isOk:
      echo "  input[", i, "]: ", nameRes.get, " frame_size=", sizeRes.get

  for i in 0..<outStreams.len:
    let s = outStreams[i]
    let nameRes = s.name()
    let sizeRes = s.frameSize()
    if nameRes.isOk and sizeRes.isOk:
      echo "  output[", i, "]: ", nameRes.get, " frame_size=", sizeRes.get

  discard outStreams.close()
  discard inStreams.close()
  discard ngObj.close()
  discard vdevObj.close()
  discard hefObj.close()
