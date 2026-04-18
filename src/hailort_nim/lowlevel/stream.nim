import ./network_group
import ../bindings/[c_api, types]
import ../internal/[error, helper]

# ==============================================================================
# Public type aliases
# ==============================================================================
type
  InputStreamObj* = object
    raw*: hailo_input_stream
  InputStream* = ref InputStreamObj

  OutputStreamObj* = object
    raw*: hailo_output_stream
  OutputStream* = ref OutputStreamObj

# ==============================================================================
# Name / info helpers
# ==============================================================================

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc name*(info: StreamInfo): string =
  cCharArrayToString(info.name)

# ==============================================================================
# Raw handles
# ==============================================================================

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc rawHandle*(s: InputStream): hailo_input_stream {.inline.} =
  if s.isNil: nil else: s.raw

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc rawHandle*(s: OutputStream): hailo_output_stream {.inline.} =
  if s.isNil: nil else: s.raw

# ==============================================================================
# Create / lookup
# ==============================================================================

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc getInputStream*(ng: NetworkGroup, name: string): HE[InputStream] =
  if ng.isNil or ng.rawHandle.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "network group is nil").err
  if name.len == 0:
    return makeError(HAILO_INVALID_ARGUMENT, "stream name is empty").err
  var raw: hailo_input_stream = nil
  let res = hailo_get_input_stream(ng.rawHandle, name.cstring, addr raw)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  result = InputStream(raw: raw).ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc getOutputStream*(ng: NetworkGroup, name: string): HE[OutputStream] =
  if ng.isNil or ng.rawHandle.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "network group is nil").err
  if name.len == 0:
    return makeError(HAILO_INVALID_ARGUMENT, "stream name is empty").err
  var raw: hailo_output_stream = nil
  let res = hailo_get_output_stream(ng.rawHandle, name.cstring, addr raw)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  result = OutputStream(raw: raw).ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc getInputStreams*(ng: NetworkGroup): HE[seq[InputStream]] =
  let infosRes = ng.getInputStreamInfos()
  if infosRes.isErr:
    return infosRes.error.err
  var streams = newSeq[InputStream](infosRes.get.len)
  for i, info in infosRes.get:
    let name = info.name.cCharArrayToString
    let streamRes = ng.getInputStream(name)
    if streamRes.isErr:
      return streamRes.error.err
    streams[i] = streamRes.get
  result = streams.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc getOutputStreams*(ng: NetworkGroup): HE[seq[OutputStream]] =
  let infosRes = ng.getOutputStreamInfos()
  if infosRes.isErr:
    return infosRes.error.err
  var streams = newSeq[OutputStream](infosRes.get.len)
  for i, info in infosRes.get:
    let name = info.name.cCharArrayToString
    let streamRes = ng.getOutputStream(name)
    if streamRes.isErr:
      return streamRes.error.err
    streams[i] = streamRes.get
  result = streams.ok

# ==============================================================================
# Input stream info / io
# ==============================================================================

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc setTimeout*(s: InputStream, timeoutMs: uint32): HE[void] =
  if s.isNil or s.raw.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "input stream is nil").err
  check(hailo_set_input_stream_timeout(s.raw, timeoutMs))

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc frameSize*(s: InputStream): int =
  if s.isNil or s.raw.isNil:
    return 0
  result = int(hailo_get_input_stream_frame_size(s.raw))

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc info*(s: InputStream): HE[StreamInfo] =
  if s.isNil or s.raw.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "input stream is nil").err
  var info: StreamInfo
  let res = hailo_get_input_stream_info(s.raw, addr info)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  result = info.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc quantInfos*(s: InputStream): HE[seq[QuantInfo]] =
  if s.isNil or s.raw.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "input stream is nil").err
  var count: csize_t = 8
  while true:
    var infos = newSeq[QuantInfo](int(count))
    var actualCount = count
    let res = hailo_get_input_stream_quant_infos(s.raw, infos[0].addr,
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
proc name*(s: InputStream): HE[string] =
  let infoRes = s.info()
  if infoRes.isErr:
    return infoRes.error.err
  result = infoRes.get.name.cCharArrayToString.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc write*(s: InputStream, buffer: pointer, size: Natural): HE[void] =
  if s.isNil or s.raw.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "input stream is nil").err
  check(hailo_stream_write_raw_buffer(s.raw, buffer, csize_t(size)))

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc write*(s: InputStream, data: openArray[byte]): HE[void] =
  if data.len == 0:
    return makeError(HAILO_INVALID_ARGUMENT, "input buffer is empty").err
  result = s.write(unsafeAddr data[0], data.len)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc waitForAsyncReady*(s: InputStream, transferSize: Natural, timeoutMs: uint32):
    HE[void] =
  if s.isNil or s.raw.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "input stream is nil").err
  check(hailo_stream_wait_for_async_input_ready(s.raw, csize_t(transferSize),
      timeoutMs))

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc asyncMaxQueueSize*(s: InputStream): HE[int] =
  if s.isNil or s.raw.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "input stream is nil").err
  var queueSize: csize_t
  let res = hailo_input_stream_get_async_max_queue_size(s.raw, addr queueSize)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  result = int(queueSize).ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc writeAsync*(s: InputStream, buffer: pointer, size: Natural,
    userCallback: StreamWriteAsyncCallback, opaque: pointer = nil): HE[void] =
  if s.isNil or s.raw.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "input stream is nil").err
  check(hailo_stream_write_raw_buffer_async(s.raw, buffer, csize_t(size),
      userCallback, opaque))

# ==============================================================================
# Output stream info / io
# ==============================================================================

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc setTimeout*(s: OutputStream, timeoutMs: uint32): HE[void] =
  if s.isNil or s.raw.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "output stream is nil").err
  check(hailo_set_output_stream_timeout(s.raw, timeoutMs))

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc frameSize*(s: OutputStream): int =
  if s.isNil or s.raw.isNil:
    return 0
  result = int(hailo_get_output_stream_frame_size(s.raw))

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc info*(s: OutputStream): HE[StreamInfo] =
  if s.isNil or s.raw.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "output stream is nil").err
  var info: StreamInfo
  let res = hailo_get_output_stream_info(s.raw, addr info)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  result = info.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc quantInfos*(s: OutputStream): HE[seq[QuantInfo]] =
  if s.isNil or s.raw.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "output stream is nil").err
  var count: csize_t = 8
  while true:
    var infos = newSeq[QuantInfo](int(count))
    var actualCount = count
    let res = hailo_get_output_stream_quant_infos(s.raw, infos[0].addr,
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
proc name*(s: OutputStream): HE[string] =
  let infoRes = s.info()
  if infoRes.isErr:
    return infoRes.error.err
  result = infoRes.get.name.cCharArrayToString.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc read*(s: OutputStream, buffer: pointer, size: Natural): HE[void] =
  if s.isNil or s.raw.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "output stream is nil").err
  check(hailo_stream_read_raw_buffer(s.raw, buffer, csize_t(size)))

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc read*(s: OutputStream, size: Natural): HE[seq[byte]] =
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
proc waitForAsyncReady*(s: OutputStream, transferSize: Natural, timeoutMs: uint32):
    HE[void] =
  if s.isNil or s.raw.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "output stream is nil").err
  check(hailo_stream_wait_for_async_output_ready(s.raw, csize_t(transferSize),
      timeoutMs))

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc asyncMaxQueueSize*(s: OutputStream): HE[int] =
  if s.isNil or s.raw.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "output stream is nil").err
  var queueSize: csize_t
  let res = hailo_output_stream_get_async_max_queue_size(s.raw, addr queueSize)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  result = int(queueSize).ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc readAsync*(s: OutputStream, buffer: pointer, size: Natural,
    userCallback: StreamReadAsyncCallback, opaque: pointer = nil): HE[void] =
  if s.isNil or s.raw.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "output stream is nil").err
  check(hailo_stream_read_raw_buffer_async(s.raw, buffer, csize_t(size),
      userCallback, opaque))

# ==============================================================================
# Static helpers
# ==============================================================================

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc hostFrameSize*(info: StreamInfo, transformParams: TransformParams): int =
  let infoCopy = info
  let paramsCopy = transformParams
  result = int(hailo_get_host_frame_size(addr infoCopy, addr paramsCopy))

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc hostFrameSize*(info: StreamInfo): int =
  let infoCopy = info
  result = int(hailo_get_host_frame_size(addr infoCopy, nil))


# ==============================================================================
# Main test
# ==============================================================================

when isMainModule:
  import std/os
  import ./hef
  import ./vdevice

  if paramCount() < 1:
    echo "Usage: ", getAppFilename(), " <model.hef>"
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

  let inStreamsRes = ngObj.getInputStreams()
  if inStreamsRes.isErr:
    echo "Error getting input streams: ", inStreamsRes.error
    discard ngObj.close()
    discard vdevObj.close()
    discard hefObj.close()
    quit 1
  let inStreams = inStreamsRes.get
  echo "Input streams: ", inStreams.len

  for i, s in inStreams:
    let nameRes = s.name()
    let infoRes = s.info()
    let qRes = s.quantInfos()
    echo "  input[", i, "]"
    if nameRes.isOk:
      echo "    name: ", nameRes.get
    else:
      echo "    name error: ", nameRes.error
    echo "    frame_size: ", s.frameSize()
    if infoRes.isOk:
      echo "    direction: ", ord(infoRes.get.direction)
      echo "    index: ", infoRes.get.index
    else:
      echo "    info error: ", infoRes.error
    if qRes.isOk:
      echo "    quant_infos: ", qRes.get.len
    else:
      echo "    quant_infos error: ", qRes.error

  let outStreamsRes = ngObj.getOutputStreams()
  if outStreamsRes.isErr:
    echo "Error getting output streams: ", outStreamsRes.error
    discard ngObj.close()
    discard vdevObj.close()
    discard hefObj.close()
    quit 1
  let outStreams = outStreamsRes.get
  echo "Output streams: ", outStreams.len

  for i, s in outStreams:
    let nameRes = s.name()
    let infoRes = s.info()
    let qRes = s.quantInfos()
    echo "  output[", i, "]"
    if nameRes.isOk:
      echo "    name: ", nameRes.get
    else:
      echo "    name error: ", nameRes.error
    echo "    frame_size: ", s.frameSize()
    if infoRes.isOk:
      echo "    direction: ", ord(infoRes.get.direction)
      echo "    index: ", infoRes.get.index
    else:
      echo "    info error: ", infoRes.error
    if qRes.isOk:
      echo "    quant_infos: ", qRes.get.len
    else:
      echo "    quant_infos error: ", qRes.error

  echo "Smoke test completed (metadata only, no frame I/O performed)"

  discard ngObj.close()
  discard vdevObj.close()
  discard hefObj.close()
