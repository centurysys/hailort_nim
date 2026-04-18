import ../bindings/c_api
import ./error

# ==============================================================================
# Helpers
# ==============================================================================

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc check*(res: hailo_status): HE[void] {.inline.} =
  if res == HAILO_SUCCESS:
    okVoid()
  else:
    makeError(res, $res).err

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc cCharArrayToString*[N: static int](buf: array[N, cschar], len: Natural):
    string =
  let n = min(len, N)
  result = newString(n)
  if n > 0:
    copyMem(addr result[0], unsafeAddr buf[0], n)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc cCharArrayToString*[N: static int](buf: array[N, cschar]): string =
  var n = 0
  while n < N and buf[n] != 0:
    inc n
  result = cCharArrayToString(buf, n)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc bytesToHex*(data: openArray[uint8]): string =
  const hex = "0123456789abcdef"
  result = newStringOfCap(data.len * 2)
  for b in data:
    result.add(hex[int(b shr 4)])
    result.add(hex[int(b and 0x0f)])

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc optCString*(s: string): cstring {.inline.} =
  result = if s.len == 0:
      nil
    else:
      s.cstring
