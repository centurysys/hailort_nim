import ../lowlevel

# ==============================================================================
# Public types
# ==============================================================================

type
  DeviceTemperature* = object
    ts0C*: float32
    ts1C*: float32
    sampleCount*: uint16

  DeviceStats* = object
    temperature*: DeviceTemperature
    throttlingActive*: bool
    hasPower*: bool
    powerW*: float32

# ==============================================================================
# Temperature helpers
# ==============================================================================

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc toDeviceTemperature*(info: ChipTemperatureInfo): DeviceTemperature =
  result = DeviceTemperature(
    ts0C: info.ts0_temperature,
    ts1C: info.ts1_temperature,
    sampleCount: info.sample_count,
  )

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc averageC*(temperature: DeviceTemperature): float32 =
  result = (temperature.ts0C + temperature.ts1C) / 2.0'f32

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc maxC*(temperature: DeviceTemperature): float32 =
  if temperature.ts0C >= temperature.ts1C:
    result = temperature.ts0C
  else:
    result = temperature.ts1C

# ==============================================================================
# Device stats
# ==============================================================================

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc getDeviceStats*(
    device: Device,
    readPower = false,
    dvm: DvmOptions = HAILO_DVM_OPTIONS_AUTO,
    measurementType: PowerMeasurementType = HAILO_POWER_MEASUREMENT_TYPES_POWER,
): HE[DeviceStats] =
  if device.isNil or device.rawHandle.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "device is nil").err

  let tempRes = device.getChipTemperature()
  if tempRes.isErr:
    return tempRes.error.err

  let throttlingRes = device.getThrottlingState()
  if throttlingRes.isErr:
    return throttlingRes.error.err

  result = DeviceStats(
    temperature: tempRes.get.toDeviceTemperature(),
    throttlingActive: throttlingRes.get,
    hasPower: false,
    powerW: 0.0'f32,
  ).ok

  if readPower:
    let powerRes = device.powerMeasurement(dvm, measurementType)

    if powerRes.isOk:
      result = DeviceStats(
        temperature: tempRes.get.toDeviceTemperature(),
        throttlingActive: throttlingRes.get,
        hasPower: true,
        powerW: powerRes.get,
      ).ok
    elif powerRes.error.status == HAILO_UNSUPPORTED_OPCODE:
      result = DeviceStats(
        temperature: tempRes.get.toDeviceTemperature(),
        throttlingActive: throttlingRes.get,
        hasPower: false,
        powerW: 0.0'f32,
      ).ok
    else:
      return powerRes.error.err

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc getDeviceStatsNoPower*(device: Device): HE[DeviceStats] =
  result = device.getDeviceStats(readPower = false)
