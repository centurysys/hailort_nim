import ../lowlevel
import ./device_stats

# ==============================================================================
# HailoRuntime device helpers:
# ==============================================================================

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc physicalDevices*(runtime: HailoRuntime): HE[seq[Device]] =
  ## Return the physical devices owned by this runtime's vdevice.
  if runtime.isNil or not runtime.isOpen():
    return makeError(HAILO_INVALID_ARGUMENT, "runtime is not open").err

  let vdevice = runtime.rawVdevice()
  if vdevice.isNil or vdevice.rawHandle.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "runtime vdevice is nil").err

  result = vdevice.getPhysicalDevices()

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc physicalDevice*(runtime: HailoRuntime; index = 0): HE[Device] =
  ## Return one physical device owned by this runtime's vdevice.
  let devicesRes = runtime.physicalDevices()
  if devicesRes.isErr:
    return devicesRes.error.err

  let devices = devicesRes.get
  if index < 0 or index >= devices.len:
    return makeError(
      HAILO_INVALID_ARGUMENT,
      "physical device index is out of range"
    ).err

  result = devices[index].ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc getFirstPhysicalDevice(runtime: HailoRuntime): HE[Device] =
  let devices = ?runtime.physicalDevices()

  if devices.len == 0:
    return err(makeError(
      HAILO_NOT_FOUND,
      "getFirstPhysicalDevice: no physical Hailo device found"
    ))

  result = ok(devices[0])

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc getDeviceStats*(
  runtime: HailoRuntime;
  index = 0;
  includePower = false
): HE[DeviceStats] =
  ## Read aggregated status information from a physical device owned by runtime.
  ##
  ## This is a convenience wrapper around device_stats.getDeviceStats(Device).
  ## Policy decisions such as throttling, restart, or frame skipping should stay
  ## in the application / vision-pipeline layer.
  let deviceRes = runtime.physicalDevice(index)
  if deviceRes.isErr:
    return deviceRes.error.err

  result = device_stats.getDeviceStats(deviceRes.get, includePower)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc getDeviceStatsAll*(
  runtime: HailoRuntime;
  includePower = false
): HE[seq[DeviceStats]] =
  ## Read aggregated status information from all physical devices owned by
  ## runtime.
  let devicesRes = runtime.physicalDevices()
  if devicesRes.isErr:
    return devicesRes.error.err

  let devices = devicesRes.get
  var stats = newSeq[DeviceStats](devices.len)

  for i in 0 ..< devices.len:
    let statsRes = device_stats.getDeviceStats(devices[i],
        readPower = includePower)
    if statsRes.isErr:
      return statsRes.error.err
    stats[i] = statsRes.get

  result = stats.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc getRuntimeChipTemperature*(
  runtime: HailoRuntime;
  index = 0
): HE[ChipTemperatureInfo] =
  ## Convenience wrapper for reading chip temperature through HailoRuntime.
  let deviceRes = runtime.physicalDevice(index)
  if deviceRes.isErr:
    return deviceRes.error.err

  result = deviceRes.get.getChipTemperature()

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc getRuntimeThrottlingState*(runtime: HailoRuntime; index = 0): HE[bool] =
  ## Convenience wrapper for reading throttling state through HailoRuntime.
  let deviceRes = runtime.physicalDevice(index)
  if deviceRes.isErr:
    return deviceRes.error.err

  result = deviceRes.get.getThrottlingState()

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc powerMeasurement*(
    runtime: HailoRuntime;
    dvm: DvmOptions = HAILO_DVM_OPTIONS_AUTO;
    measurementType: PowerMeasurementType = HAILO_POWER_MEASUREMENT_TYPES_POWER
): HE[float32] =
  let device = ?runtime.getFirstPhysicalDevice()
  result = device.powerMeasurement(
    dvm = dvm,
    measurementType = measurementType
  )
