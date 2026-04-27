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

    let res = hailo_get_physical_devices(
      vdevice.vdev,
      rawDevices[0].addr,
      addr actualCount,
    )
    if res == HAILO_INSUFFICIENT_BUFFER:
      count = actualCount
      continue

    if res != HAILO_SUCCESS:
      return makeError(res, $res).err

    var devices = newSeq[Device](int(actualCount))
    for i in 0 ..< int(actualCount):
      devices[i] = Device(dev: rawDevices[i], owned: false)

    return devices.ok
