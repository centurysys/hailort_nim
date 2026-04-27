import std/strformat
import hailort_nim

# ==============================================================================
# Main:
# ==============================================================================
proc main(): int =
  let runtimeRes = HailoRuntime.open()
  if runtimeRes.isErr:
    echo "Failed to open runtime: ", runtimeRes.error
    return 1

  let runtime = runtimeRes.get
  #defer:
  #  discard runtime.close()

  # --------------------------------------------------------------------------
  # Device list
  # --------------------------------------------------------------------------
  let devicesRes = runtime.physicalDevices()
  if devicesRes.isErr:
    echo "Failed to get devices: ", devicesRes.error
    return 1

  let devices = devicesRes.get
  echo fmt"device count: {devices.len}"

  if devices.len == 0:
    echo "No Hailo devices found"
    return 1

  # --------------------------------------------------------------------------
  # Device stats
  # --------------------------------------------------------------------------
  let statsRes = runtime.getDeviceStats()
  if statsRes.isErr:
    echo "Failed to get device stats: ", statsRes.error
    return 1

  let stats = statsRes.get

  echo "---- Device Stats ----"
  echo fmt"temperature ts0: {stats.temperature.ts0C:.2f} C"
  echo fmt"temperature ts1: {stats.temperature.ts1C:.2f} C"
  echo fmt"sample count   : {stats.temperature.sampleCount}"

  let avgTemp = (stats.temperature.ts0C + stats.temperature.ts1C) / 2
  echo fmt"avg temperature: {avgTemp:.2f} C"

  echo fmt"throttling     : {stats.throttlingActive}"

  # --------------------------------------------------------------------------
  # Power measurement (optional)
  # --------------------------------------------------------------------------
  if stats.hasPower:
    let powerRes = runtime.powerMeasurement()
    if powerRes.isOk:
      echo fmt"power          : {powerRes.get:.3f} W"
    else:
      echo "power measurement failed: ", powerRes.error
  else:
    echo "power measurement not available"

  return 0


# ==============================================================================
# Entry point:
# ==============================================================================
when isMainModule:
  quit(main())
