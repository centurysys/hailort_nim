import ./hef
import ./vdevice
import ../bindings/[c_api, types]
import ../internal/[error, helper]

# ==============================================================================
# Public type aliases
# ==============================================================================
type
  NetworkGroupObj* = object
    ng*: hailo_configured_network_group
  NetworkGroup* = ref NetworkGroupObj

  ActivatedNetworkGroupObj* = object
    ang*: hailo_activated_network_group
  ActivatedNetworkGroup* = ref ActivatedNetworkGroupObj

# ==============================================================================
# Helpers
# ==============================================================================

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc `=destroy`(obj: var ActivatedNetworkGroupObj) =
  if obj.ang != nil:
    discard hailo_deactivate_network_group(obj.ang)
    obj.ang = nil

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc rawHandle*(ng: NetworkGroup): hailo_configured_network_group {.inline.} =
  if ng.isNil:
    nil
  else:
    ng.ng

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc rawHandle*(ang: ActivatedNetworkGroup): hailo_activated_network_group {.inline.} =
  if ang.isNil:
    nil
  else:
    ang.ang

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc name*(item: OutputVstreamNameByGroup): string =
  cCharArrayToString(item.name)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc close*(ng: NetworkGroup): HE[void] =
  if ng.isNil or ng.ng.isNil:
    return okVoid()
  let res = hailo_shutdown_network_group(ng.ng)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  ng.ng = nil
  okVoid()

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc close*(ang: ActivatedNetworkGroup): HE[void] =
  if ang.isNil or ang.ang.isNil:
    return okVoid()
  let res = hailo_deactivate_network_group(ang.ang)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  ang.ang = nil
  okVoid()

# ==============================================================================
# Configure / activation
# ==============================================================================

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc configure*(vdevice: Vdevice, hef: Hef): HE[seq[NetworkGroup]] =
  if vdevice.isNil or vdevice.rawHandle.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "vdevice is nil").err
  if hef.isNil or hef.rawHandle.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "hef is nil").err
  var params: hailo_configure_params_t
  let initRes = hailo_init_configure_params_by_vdevice(hef.rawHandle,
      vdevice.rawHandle, addr params)
  if initRes != HAILO_SUCCESS:
    return makeError(initRes, $initRes).err
  var count: csize_t = 8
  while true:
    var rawGroups = newSeq[hailo_configured_network_group](int(count))
    var actualCount = count
    let res = hailo_configure_vdevice(vdevice.rawHandle, hef.rawHandle,
        addr params, rawGroups[0].addr, addr actualCount)
    if res == HAILO_INSUFFICIENT_BUFFER:
      count = actualCount
      continue
    if res != HAILO_SUCCESS:
      return makeError(res, $res).err
    var groups = newSeq[NetworkGroup](int(actualCount))
    for i in 0..<int(actualCount):
      groups[i] = NetworkGroup(ng: rawGroups[i])
    return groups.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc configureOne*(vdevice: Vdevice, hef: Hef): HE[NetworkGroup] =
  let groupsRes = configure(vdevice, hef)
  if groupsRes.isErr:
    return groupsRes.error.err
  let groups = groupsRes.get
  if groups.len == 0:
    return makeError(HAILO_NOT_FOUND, "no network groups returned").err
  if groups.len > 1:
    return makeError(HAILO_INVALID_OPERATION,
      "multiple network groups returned, use configure() instead").err
  groups[0].ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc initConfigureNetworkGroupParams*(hef: Hef, streamInterface: hailo_stream_interface_t,
    networkGroupName = ""): HE[ConfigureNetworkGroupParams] =
  if hef.isNil or hef.rawHandle.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "hef is nil").err
  var params: ConfigureNetworkGroupParams
  let res = hailo_init_configure_network_group_params(hef.rawHandle, streamInterface,
    networkGroupName.optCString, addr params)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  params.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc initActivateParams*(): ActivateNetworkGroupParams {.inline.} =
  ActivateNetworkGroupParams()

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc activate*(ng: NetworkGroup, params: ActivateNetworkGroupParams = initActivateParams()):
    HE[ActivatedNetworkGroup] =
  if ng.isNil or ng.ng.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "network group is nil").err
  var p = params
  var raw: hailo_activated_network_group = nil
  let res = hailo_activate_network_group(ng.ng, addr p, addr raw)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  ActivatedNetworkGroup(ang: raw).ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc waitForActivation*(ng: NetworkGroup, timeoutMs: uint32): HE[void] =
  if ng.isNil or ng.ng.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "network group is nil").err
  check hailo_wait_for_network_group_activation(ng.ng, timeoutMs)

# ==============================================================================
# Query / info
# ==============================================================================

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc getAllStreamInfos*(ng: NetworkGroup): HE[seq[StreamInfo]] =
  if ng.isNil or ng.ng.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "network group is nil").err
  var count: csize_t = 8
  while true:
    var infos = newSeq[StreamInfo](int(count))
    var actualCount = count
    let res = hailo_network_group_get_all_stream_infos(ng.ng, infos[0].addr, count,
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
proc getInputStreamInfos*(ng: NetworkGroup): HE[seq[StreamInfo]] =
  if ng.isNil or ng.ng.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "network group is nil").err
  var count: csize_t = 8
  while true:
    var infos = newSeq[StreamInfo](int(count))
    var actualCount = count
    let res = hailo_network_group_get_input_stream_infos(ng.ng, infos[0].addr,
        count, addr actualCount)
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
proc getOutputStreamInfos*(ng: NetworkGroup): HE[seq[StreamInfo]] =
  if ng.isNil or ng.ng.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "network group is nil").err
  var count: csize_t = 8
  while true:
    var infos = newSeq[StreamInfo](int(count))
    var actualCount = count
    let res = hailo_network_group_get_output_stream_infos(ng.ng, infos[0].addr,
        count, addr actualCount)
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
proc getNetworkInfos*(ng: NetworkGroup): HE[seq[NetworkInfo]] =
  if ng.isNil or ng.ng.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "network group is nil").err
  var count: csize_t = 8
  while true:
    var infos = newSeq[NetworkInfo](int(count))
    var actualCount = count
    let res = hailo_get_network_infos(ng.ng, infos[0].addr, addr actualCount)
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
proc getLatencyMeasurement*(ng: NetworkGroup, networkName = ""):
    HE[LatencyMeasurementResult] =
  if ng.isNil or ng.ng.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "network group is nil").err
  var value: LatencyMeasurementResult
  let res = hailo_get_latency_measurement(ng.ng, networkName.optCString, addr value)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  value.ok

# ==============================================================================
# Scheduler / control
# ==============================================================================

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc setSchedulerTimeout*(ng: NetworkGroup, timeoutMs: uint32, networkName = ""):
    HE[void] =
  if ng.isNil or ng.ng.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "network group is nil").err
  check hailo_set_scheduler_timeout(ng.ng, timeoutMs, networkName.optCString)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc setSchedulerThreshold*(ng: NetworkGroup, threshold: uint32, networkName = ""):
    HE[void] =
  if ng.isNil or ng.ng.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "network group is nil").err
  check hailo_set_scheduler_threshold(ng.ng, threshold, networkName.optCString)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc setSchedulerPriority*(ng: NetworkGroup, priority: uint8, networkName = ""):
    HE[void] =
  if ng.isNil or ng.ng.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "network group is nil").err
  check hailo_set_scheduler_priority(ng.ng, priority, networkName.optCString)

# ==============================================================================
# VStream params helpers
# ==============================================================================

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc makeInputVstreamParams*(ng: NetworkGroup, formatType: hailo_format_type_t = HAILO_FORMAT_TYPE_AUTO):
    HE[seq[InputVstreamParamsByName]] =
  if ng.isNil or ng.ng.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "network group is nil").err
  var count: csize_t = 8
  while true:
    var params = newSeq[InputVstreamParamsByName](int(count))
    var actualCount = count
    let res = hailo_make_input_vstream_params(ng.ng, false, formatType,
        params[0].addr, addr actualCount)
    if res == HAILO_INSUFFICIENT_BUFFER:
      count = actualCount
      continue
    if res != HAILO_SUCCESS:
      return makeError(res, $res).err
    params.setLen(int(actualCount))
    return params.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc makeOutputVstreamParams*(ng: NetworkGroup, formatType: hailo_format_type_t = HAILO_FORMAT_TYPE_AUTO):
    HE[seq[OutputVstreamParamsByName]] =
  if ng.isNil or ng.ng.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "network group is nil").err
  var count: csize_t = 8
  while true:
    var params = newSeq[OutputVstreamParamsByName](int(count))
    var actualCount = count
    let res = hailo_make_output_vstream_params(ng.ng, false, formatType,
        params[0].addr, addr actualCount)
    if res == HAILO_INSUFFICIENT_BUFFER:
      count = actualCount
      continue
    if res != HAILO_SUCCESS:
      return makeError(res, $res).err
    params.setLen(int(actualCount))
    return params.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc getOutputVstreamGroups*(ng: NetworkGroup): HE[seq[OutputVstreamNameByGroup]] =
  if ng.isNil or ng.ng.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "network group is nil").err
  var count: csize_t = 8
  while true:
    var items = newSeq[OutputVstreamNameByGroup](int(count))
    var actualCount = count
    let res = hailo_get_output_vstream_groups(ng.ng, items[0].addr, addr actualCount)
    if res == HAILO_INSUFFICIENT_BUFFER:
      count = actualCount
      continue
    if res != HAILO_SUCCESS:
      return makeError(res, $res).err
    items.setLen(int(actualCount))
    return items.ok

# ==============================================================================
# Main test
# ==============================================================================

when isMainModule:
  import std/os

  if paramCount() < 1:
    echo "Usage: network_group <model.hef>"
    quit 1

  let hefPath = paramStr(1)
  echo "Opening HEF: ", hefPath

  let hefRes = openHef(hefPath)
  if hefRes.isErr:
    echo "Error: ", hefRes.error
    quit 1

  let hefobj = hefRes.get
  echo "HEF opened"

  let vdevRes = createVdevice()
  if vdevRes.isErr:
    echo "Error creating VDevice: ", vdevRes.error
    quit 1

  let vdev = vdevRes.get
  echo "VDevice created"

  let groupsRes = configure(vdev, hefobj)
  if groupsRes.isErr:
    echo "Error configuring: ", groupsRes.error
    quit 1

  let groups = groupsRes.get
  echo "Configured network groups: ", groups.len

  for i, ng in groups:
    echo "Network group #", i

    let allRes = ng.getAllStreamInfos()
    if allRes.isOk:
      echo "  All streams: ", allRes.get.len
      for info in allRes.get:
        echo "  - ", info.name.cCharArrayToString
    else:
      echo "  Failed to get all streams: ", allRes.error

    let inRes = ng.getInputStreamInfos()
    if inRes.isOk:
      echo "  Input streams: ", inRes.get.len
      for info in inRes.get:
        echo "  - ", info.name.cCharArrayToString
    else:
      echo "  Failed to get input streams: ", inRes.error

    let outRes = ng.getOutputStreamInfos()
    if outRes.isOk:
      echo "  Output streams: ", outRes.get.len
      for info in outRes.get:
        echo "  - ", info.name.cCharArrayToString
    else:
      echo "  Failed to get output streams: ", outRes.error

    let netRes = ng.getNetworkInfos()
    if netRes.isOk:
      echo "  Networks: ", netRes.get.len
      for info in netRes.get:
        echo "  - ", info.name.cCharArrayToString
    else:
      echo "  Failed to get network infos: ", netRes.error

    let inParamsRes = ng.makeInputVstreamParams()
    if inParamsRes.isOk:
      echo "  Input vstream params: ", inParamsRes.get.len
    else:
      echo "  Failed to make input vstream params: ", inParamsRes.error

    let outParamsRes = ng.makeOutputVstreamParams()
    if outParamsRes.isOk:
      echo "  Output vstream params: ", outParamsRes.get.len
    else:
      echo "  Failed to make output vstream params: ", outParamsRes.error

  discard vdev.close()
  discard hefobj.close()
