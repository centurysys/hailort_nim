import ../bindings/[c_api, types]
import ../internal/[error, helper]

# ==============================================================================
# Public type aliases
# ==============================================================================
type
  HefObj* = object
    hef*: hailo_hef
  Hef* = ref HefObj

# ==============================================================================
# Helpers
# ==============================================================================

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc `=destroy`(obj: var HefObj) =
  if obj.hef != nil:
    discard hailo_release_hef(obj.hef)
    obj.hef = nil

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc close*(hef: Hef): HE[void] =
  if hef.isNil or hef.hef.isNil:
    return okVoid()

  let res = hailo_release_hef(hef.hef)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err

  hef.hef = nil
  okVoid()

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc rawHandle*(hef: Hef): hailo_hef {.inline.} =
  if hef.isNil:
    nil
  else:
    hef.hef

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc `$`*(name: LayerName): string =
  cCharArrayToString(name.name)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc name*(info: StreamInfo): string =
  cCharArrayToString(info.name)

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
proc name*(info: NetworkGroupInfo): string =
  cCharArrayToString(info.name)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc name*(info: NetworkInfo): string =
  cCharArrayToString(info.name)

# ==============================================================================
# Creating / releasing HEF objects
# ==============================================================================

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc openHef*(fileName: string): HE[Hef] =
  var raw: hailo_hef = nil
  let res = hailo_create_hef_file(addr raw, fileName.cstring)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  (Hef(hef: raw)).ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc openHef*(buffer: openArray[byte]): HE[Hef] =
  if buffer.len == 0:
    return makeError(HAILO_INVALID_ARGUMENT, "buffer is empty").err
  var raw: hailo_hef = nil
  let res = hailo_create_hef_buffer(addr raw, unsafeAddr buffer[0],
      csize_t(buffer.len))
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  (Hef(hef: raw)).ok

# ==============================================================================
# Stream / vstream infos
# ==============================================================================

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc getAllStreamInfos*(hef: Hef, networkGroupName = ""): HE[seq[StreamInfo]] =
  if hef.isNil or hef.hef.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "hef is nil").err
  var count: csize_t = 8
  while true:
    var infos = newSeq[StreamInfo](int(count))
    var actualCount = count
    let res = hailo_hef_get_all_stream_infos(hef.hef, networkGroupName.optCString,
      infos[0].addr, count, addr actualCount)
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
proc getStreamInfoByName*(hef: Hef, networkGroupName, streamName: string,
    direction: hailo_stream_direction_t): HE[StreamInfo] =
  if hef.isNil or hef.hef.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "hef is nil").err
  var info: StreamInfo
  let res = hailo_hef_get_stream_info_by_name(hef.hef, networkGroupName.optCString,
    streamName.cstring, direction, addr info)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  info.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc getAllVstreamInfos*(hef: Hef, networkGroupName = ""): HE[seq[VstreamInfo]] =
  if hef.isNil or hef.hef.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "hef is nil").err
  var count: csize_t = 8
  while true:
    var infos = newSeq[VstreamInfo](int(count))
    var actualCount = count
    let res = hailo_hef_get_all_vstream_infos(hef.hef, networkGroupName.optCString,
      infos[0].addr, addr actualCount)
    if res == HAILO_INSUFFICIENT_BUFFER:
      count = actualCount
      continue
    if res != HAILO_SUCCESS:
      return makeError(res, $res).err
    infos.setLen(int(actualCount))
    return infos.ok

# ==============================================================================
# Name mapping helpers
# ==============================================================================

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc getVstreamNameFromOriginalName*(hef: Hef, networkGroupName,
    originalName: string): HE[string] =
  if hef.isNil or hef.hef.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "hef is nil").err
  var name: LayerName
  let res = hailo_hef_get_vstream_name_from_original_name(hef.hef,
    networkGroupName.optCString, originalName.cstring, addr name)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  ($name).ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc getOriginalNamesFromVstreamName*(hef: Hef, networkGroupName,
    vstreamName: string): HE[seq[string]] =
  if hef.isNil or hef.hef.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "hef is nil").err
  var count: csize_t = 8
  while true:
    var names = newSeq[LayerName](int(count))
    var actualCount = count
    let res = hailo_hef_get_original_names_from_vstream_name(hef.hef,
        networkGroupName.optCString, vstreamName.cstring, names[0].addr,
        addr actualCount)
    if res == HAILO_INSUFFICIENT_BUFFER:
      count = actualCount
      continue
    if res != HAILO_SUCCESS:
      return makeError(res, $res).err
    let count = int(actualCount)
    var name = newSeq[string](count)
    for i in 0..<count:
      name[i] = $names[i]
    return name.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc getVstreamNamesFromStreamName*(hef: Hef, networkGroupName,
    streamName: string): HE[seq[string]] =
  if hef.isNil or hef.hef.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "hef is nil").err
  var count: csize_t = 8
  while true:
    var names = newSeq[LayerName](int(count))
    var actualCount = count
    let res = hailo_hef_get_vstream_names_from_stream_name(hef.hef,
      networkGroupName.optCString, streamName.cstring, names[0].addr,
      addr actualCount)
    if res == HAILO_INSUFFICIENT_BUFFER:
      count = actualCount
      continue
    if res != HAILO_SUCCESS:
      return makeError(res, $res).err
    let count = int(actualCount)
    var name = newSeq[string](count)
    for i in 0..<count:
      name[i] = $names[i]
    return name.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc getStreamNamesFromVstreamName*(hef: Hef, networkGroupName,
    vstreamName: string): HE[seq[string]] =
  if hef.isNil or hef.hef.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "hef is nil").err
  var count: csize_t = 8
  while true:
    var names = newSeq[LayerName](int(count))
    var actualCount = count
    let res = hailo_hef_get_stream_names_from_vstream_name(hef.hef,
      networkGroupName.optCString, vstreamName.cstring, names[0].addr,
      addr actualCount)
    if res == HAILO_INSUFFICIENT_BUFFER:
      count = actualCount
      continue
    if res != HAILO_SUCCESS:
      return makeError(res, $res).err
    let count = int(actualCount)
    var name = newSeq[string](count)
    for i in 0..<count:
      name[i] = $names[i]
    return name.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc getSortedOutputNames*(hef: Hef, networkGroupName = ""): HE[seq[string]] =
  if hef.isNil or hef.hef.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "hef is nil").err
  var count: csize_t = 8
  while true:
    var names = newSeq[LayerName](int(count))
    var actualCount = count
    let res = hailo_hef_get_sorted_output_names(hef.hef, networkGroupName.optCString,
      names[0].addr, addr actualCount)
    if res == HAILO_INSUFFICIENT_BUFFER:
      count = actualCount
      continue
    if res != HAILO_SUCCESS:
      return makeError(res, $res).err
    let count = int(actualCount)
    var name = newSeq[string](count)
    for i in 0..<count:
      name[i] = $names[i]
    return name.ok

# ==============================================================================
# Network group / network queries
# ==============================================================================

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc getBottleneckFps*(hef: Hef, networkGroupName = ""): HE[float64] =
  if hef.isNil or hef.hef.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "hef is nil").err
  var fps: float64_t
  let res = hailo_hef_get_bottleneck_fps(hef.hef, networkGroupName.optCString,
      addr fps)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  fps.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc getNetworkGroupsInfos*(hef: Hef): HE[seq[NetworkGroupInfo]] =
  if hef.isNil or hef.hef.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "hef is nil").err
  var count: csize_t = 8
  while true:
    var infos = newSeq[NetworkGroupInfo](int(count))
    var actualCount = count
    let res = hailo_get_network_groups_infos(hef.hef, infos[0].addr,
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
proc getNetworkInfos*(hef: Hef, networkGroupName = ""): HE[seq[NetworkInfo]] =
  if hef.isNil or hef.hef.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "hef is nil").err
  var count: csize_t = 8
  while true:
    var infos = newSeq[NetworkInfo](int(count))
    var actualCount = count
    let res = hailo_hef_get_network_infos(hef.hef, networkGroupName.optCString,
        infos[0].addr, addr actualCount)
    if res == HAILO_INSUFFICIENT_BUFFER:
      count = actualCount
      continue
    if res != HAILO_SUCCESS:
      return makeError(res, $res).err
    infos.setLen(int(actualCount))
    return infos.ok

# ==============================================================================
# Main test
# ==============================================================================

when isMainModule:
  import std/os

  if paramCount() < 1:
    echo "Usage: ", getAppFilename(), " <model.hef>"
    quit 1

  let hefPath = paramStr(1)
  echo "Opening HEF: ", hefPath

  let hefRes = openHef(hefPath)
  if hefRes.isErr:
    echo "Error: ", hefRes.error
    quit 1

  let hef = hefRes.get
  echo "HEF opened"

  let ngRes = getNetworkGroupsInfos(hef)
  if ngRes.isOk:
    echo "Network groups: ", ngRes.get.len
    for info in ngRes.get:
      echo "- ", name(info), " (multi_context=", info.is_multi_context, ")"
  else:
    echo "Failed to get network groups infos: ", ngRes.error

  let netRes = getNetworkInfos(hef)
  if netRes.isOk:
    echo "Networks: ", netRes.get.len
    for info in netRes.get:
      echo "- ", name(info)
  else:
    echo "Failed to get network infos: ", netRes.error

  let vstreamRes = getAllVstreamInfos(hef)
  if vstreamRes.isOk:
    echo "VStreams: ", vstreamRes.get.len
    for info in vstreamRes.get:
      echo "- ", name(info), " [network=", networkName(info), "]"
  else:
    echo "Failed to get vstream infos: ", vstreamRes.error

  discard hef.close()
