import ./device
import ../bindings/[c_api, types]
import ../internal/error

# ==============================================================================
# Public type aliases
# ==============================================================================
type
  VdeviceObj* = object
    vdev*: hailo_vdevice
  Vdevice* = ref VdeviceObj

# ==============================================================================
# Helpers
# ==============================================================================

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc `=destroy`(obj: var VdeviceObj) =
  if obj.vdev != nil:
    discard hailo_release_vdevice(obj.vdev)
    obj.vdev = nil

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc close*(vdevice: Vdevice): HE[void] =
  if vdevice.isNil or vdevice.vdev.isNil:
    return okVoid()
  let res = hailo_release_vdevice(vdevice.vdev)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  vdevice.vdev = nil
  okVoid()

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc rawHandle*(vdevice: Vdevice): hailo_vdevice {.inline.} =
  if vdevice.isNil:
    nil
  else:
    vdevice.vdev

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc hasGroupId*(params: VdeviceParams): bool {.inline.} =
  not params.group_id.isNil

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc groupId*(params: VdeviceParams): string =
  if params.group_id.isNil:
    ""
  else:
    $params.group_id

# ==============================================================================
# VDevice params
# ==============================================================================

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc initVdeviceParams*(): HE[VdeviceParams] =
  var params: VdeviceParams
  let res = hailo_init_vdevice_params(addr params)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  result = params.ok

# ==============================================================================
# Creating / releasing vdevices
# ==============================================================================

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc createVdevice*(params: VdeviceParams): HE[Vdevice] =
  var p = params
  var vdev: hailo_vdevice = nil
  let res = hailo_create_vdevice(addr p, addr vdev)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  result = (Vdevice(vdev: vdev)).ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc createVdevice*(): HE[Vdevice] =
  var vdev: hailo_vdevice = nil
  let res = hailo_create_vdevice(nil, addr vdev)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  result = (Vdevice(vdev: vdev)).ok

# ==============================================================================
# Physical devices under a vdevice
# ==============================================================================

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc getPhysicalDevices*(vdevice: Vdevice): HE[seq[Device]] =
  if vdevice.isNil or vdevice.vdev.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "vdevice is nil").err
  var count: csize_t = 8
  while true:
    var rawDevices = newSeq[hailo_device](int(count))
    var actualCount = count
    let res = hailo_get_physical_devices(vdevice.vdev, rawDevices[0].addr,
        addr actualCount)
    if res == HAILO_INSUFFICIENT_BUFFER:
      count = actualCount
      continue
    if res != HAILO_SUCCESS:
      return makeError(res, $res).err
    var devices = newSeq[Device](int(actualCount))
    for i in 0..<int(actualCount):
      devices[i] = Device(dev: rawDevices[i])
    return devices.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc getPhysicalDevicesIds*(vdevice: Vdevice): HE[seq[DeviceId]] =
  if vdevice.isNil or vdevice.vdev.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "vdevice is nil").err
  var count: csize_t = 8
  while true:
    var ids = newSeq[DeviceId](int(count))
    var actualCount = count
    let res = hailo_vdevice_get_physical_devices_ids(vdevice.vdev,
        ids[0].addr, addr actualCount)
    if res == HAILO_INSUFFICIENT_BUFFER:
      count = actualCount
      continue
    if res != HAILO_SUCCESS:
      return makeError(res, $res).err
    ids.setLen(int(actualCount))
    return ids.ok

# ==============================================================================
# Configure helpers
# ==============================================================================

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc initConfigureParams*(hef: hailo_hef, vdevice: Vdevice): HE[ConfigureParams] =
  if vdevice.isNil or vdevice.vdev.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "vdevice is nil").err
  var params: ConfigureParams
  let res = hailo_init_configure_params_by_vdevice(hef, vdevice.vdev, addr params)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  params.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc configure*(vdevice: Vdevice, hef: hailo_hef,
                params: ConfigureParams): HE[seq[ConfiguredNetworkGroup]] =
  if vdevice.isNil or vdevice.vdev.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "vdevice is nil").err
  var p = params
  var count: csize_t = 8
  while true:
    var groups = newSeq[ConfiguredNetworkGroup](int(count))
    var actualCount = count
    let res = hailo_configure_vdevice(vdevice.vdev, hef, addr p,
        groups[0].addr, addr actualCount)
    if res == HAILO_INSUFFICIENT_BUFFER:
      count = actualCount
      continue
    if res != HAILO_SUCCESS:
      return makeError(res, $res).err
    groups.setLen(int(actualCount))
    return groups.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc configure*(vdevice: Vdevice, hef: hailo_hef): HE[seq[ConfiguredNetworkGroup]] =
  let paramsRes = initConfigureParams(hef, vdevice)
  if paramsRes.isErr:
    return paramsRes.error.err
  result = configure(vdevice, hef, paramsRes.get)


# ==============================================================================
# Main test
# ==============================================================================

when isMainModule:
  echo "Initializing VDevice params..."
  let paramsRes = initVdeviceParams()
  if paramsRes.isErr:
    echo "Error: ", paramsRes.error
    quit 1

  let params = paramsRes.get
  echo "Default device_count: ", params.device_count
  echo "Default scheduling_algorithm: ", ord(params.scheduling_algorithm)
  echo "Default group_id: ", params.groupId
  echo "Default multi_process_service: ", params.multi_process_service

  echo "Creating VDevice..."
  let vdevRes = createVdevice(params)
  if vdevRes.isErr:
    echo "Error: ", vdevRes.error
    quit 1

  let vdev = vdevRes.get
  echo "VDevice created"

  let idsRes = getPhysicalDevicesIds(vdev)
  if idsRes.isOk:
    echo "Underlying physical devices: ", idsRes.get.len
    for id in idsRes.get:
      echo "- ", $id
  else:
    echo "Failed to get physical device ids: ", idsRes.error

  discard vdev.close()
