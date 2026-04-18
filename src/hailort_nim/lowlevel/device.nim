import std/net
import ../bindings/[c_api, types]
import ../internal/[error, helper]

# ==============================================================================
# Public type aliases
# ==============================================================================
type
  DeviceObj* = object
    dev*: hailo_device
  Device* = ref DeviceObj

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc `=destroy`(obj: var DeviceObj) =
  if obj.dev != nil:
    discard hailo_release_device(obj.dev)
    obj.dev = nil

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc close*(device: Device): HE[void] =
  if device.isNil or device.dev.isNil:
    return okVoid()

  let res = hailo_release_device(device.dev)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err

  device.dev = nil
  okVoid()

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc rawHandle*(device: Device): hailo_device {.inline.} =
  if device.isNil:
    nil
  else:
    device.dev

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc `$`*(id: DeviceId): string =
  cCharArrayToString(id.id)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc boardName*(identity: DeviceIdentity): string =
  cCharArrayToString(identity.board_name, identity.board_name_length.int)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc serialNumber*(identity: DeviceIdentity): string =
  cCharArrayToString(identity.serial_number, identity.serial_number_length.int)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc partNumber*(identity: DeviceIdentity): string =
  cCharArrayToString(identity.part_number, identity.part_number_length.int)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc productName*(identity: DeviceIdentity): string =
  cCharArrayToString(identity.product_name, identity.product_name_length.int)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc socIdHex*(info: ExtendedDeviceInformation): string =
  bytesToHex(info.soc_id)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc ethMacAddressHex*(info: ExtendedDeviceInformation): string =
  bytesToHex(info.eth_mac_address)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc unitLevelTrackingIdHex*(info: ExtendedDeviceInformation): string =
  bytesToHex(info.unit_level_tracking_id)

# ==============================================================================
# Scanning / opening devices
# ==============================================================================

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc scanDevices*(): HE[seq[DeviceId]] =
  var count: csize_t = 8

  while true:
    var ids = newSeq[DeviceId](int(count))
    var actualCount = count
    let res = hailo_scan_devices(nil, ids[0].addr, addr actualCount)

    if res == HAILO_INSUFFICIENT_BUFFER:
      count = actualCount
      continue

    if res != HAILO_SUCCESS:
      return makeError(res, $res).err

    ids.setLen(int(actualCount))
    return ids.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc scanPcieDevices*(): HE[seq[PcieDeviceInfo]] =
  var count: csize_t = 8

  while true:
    var infos = newSeq[PcieDeviceInfo](int(count))
    var actualCount: csize_t
    let res = hailo_scan_pcie_devices(infos[0].addr, count, addr actualCount)

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
proc scanEthernetDevices*(interfaceName: string, timeoutMs = 1000'u32):
    HE[seq[EthDeviceInfo]] =
  var count: csize_t = 8

  while true:
    var infos = newSeq[EthDeviceInfo](int(count))
    var actualCount: csize_t
    let res = hailo_scan_ethernet_devices(interfaceName.cstring, infos[0].addr,
        count, addr actualCount, timeoutMs)

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
proc parsePcieDeviceInfo*(bdf: string): HE[PcieDeviceInfo] =
  var info: PcieDeviceInfo
  let res = hailo_parse_pcie_device_info(bdf.cstring, addr info)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  info.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc createAnyDevice*(): HE[Device] =
  var dev: hailo_device = nil
  let res = hailo_create_device_by_id(nil, addr dev)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  (Device(dev: dev)).ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc createDeviceById*(id: DeviceId): HE[Device] =
  var tmp = id
  var dev: hailo_device = nil
  let res = hailo_create_device_by_id(addr tmp, addr dev)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  (Device(dev: dev)).ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc createPcieDevice*(info: PcieDeviceInfo): HE[Device] =
  var tmp = info
  var dev: hailo_device = nil
  let res = hailo_create_pcie_device(addr tmp, addr dev)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  (Device(dev: dev)).ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc createAnyPcieDevice*(): HE[Device] =
  var dev: hailo_device = nil
  let res = hailo_create_pcie_device(nil, addr dev)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  (Device(dev: dev)).ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc createEthernetDevice*(info: EthDeviceInfo): HE[Device] =
  var tmp = info
  var dev: hailo_device = nil
  let res = hailo_create_ethernet_device(addr tmp, addr dev)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  (Device(dev: dev)).ok

# ==============================================================================
# Queries / control
# ==============================================================================

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc getDeviceTypeById*(id: DeviceId): HE[DeviceType] =
  var tmp = id
  var deviceType: DeviceType
  let res = hailo_device_get_type_by_device_id(addr tmp, addr deviceType)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  deviceType.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc identify*(device: Device): HE[DeviceIdentity] =
  var identity: DeviceIdentity
  let res = hailo_identify(device.rawHandle, addr identity)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  identity.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc coreIdentify*(device: Device): HE[CoreInformation] =
  var info: CoreInformation
  let res = hailo_core_identify(device.rawHandle, addr info)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  info.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc getExtendedDeviceInformation*(device: Device): HE[ExtendedDeviceInformation] =
  var info: ExtendedDeviceInformation
  let res = hailo_get_extended_device_information(device.rawHandle, addr info)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  info.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc getDeviceId*(device: Device): HE[DeviceId] =
  var id: DeviceId
  let res = hailo_get_device_id(device.rawHandle, addr id)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  id.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc getChipTemperature*(device: Device): HE[ChipTemperatureInfo] =
  var temp: ChipTemperatureInfo
  let res = hailo_get_chip_temperature(device.rawHandle, addr temp)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  temp.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc getThrottlingState*(device: Device): HE[bool] =
  var isActive = false
  let res = hailo_get_throttling_state(device.rawHandle, addr isActive)
  if res != HAILO_SUCCESS:
    return makeError(res, $res).err
  isActive.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc setThrottlingState*(device: Device, shouldActivate: bool): HE[void] =
  check(hailo_set_throttling_state(device.rawHandle, shouldActivate))

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc setFwLogger*(device: Device, level: FwLoggerLevel, interfaceMask: uint32):
    HE[void] =
  check(hailo_set_fw_logger(device.rawHandle, level, interfaceMask))

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc reset*(device: Device, mode: ResetDeviceMode): HE[void] =
  check(hailo_reset_device(device.rawHandle, mode))

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc updateFirmware*(device: Device, firmware: openArray[byte]): HE[void] =
  if firmware.len == 0:
    return makeError(HAILO_INVALID_ARGUMENT, "firmware buffer is empty").err
  check(hailo_update_firmware(device.rawHandle, unsafeAddr firmware[0],
      uint32(firmware.len)))

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc updateSecondStage*(device: Device, secondStage: openArray[byte]): HE[void] =
  if secondStage.len == 0:
    return makeError(HAILO_INVALID_ARGUMENT, "second stage buffer is empty").err
  check(hailo_update_second_stage(device.rawHandle, unsafeAddr secondStage[0],
      uint32(secondStage.len)))


when isMainModule:
  proc main() =
    echo "Scanning devices..."

    let res = scanDevices()
    if res.isErr:
      echo "Error: ", res.error
      quit 1

    let devs = res.get
    echo "Found devices: ", devs.len

    for d in devs:
      echo "- ", d

    if devs.len == 0:
      echo "No devices found"
      quit 0

    echo "Creating first device..."

    let devRes = createDeviceById(devs[0])
    if devRes.isErr:
      echo "Error: ", devRes.error
      quit 1

    let dev = devRes.get
    echo "Device created"

    let idRes = identify(dev)
    if idRes.isOk:
      echo "Identify OK"
    else:
      echo "Identify error: ", idRes.error

    discard dev.close()

  main()
