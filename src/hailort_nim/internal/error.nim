import std/strformat
import results
import ../bindings/c_api
export results

type
  HailoError* = ref object
    status*: hailo_status
    msg*: string
    #trace*: seq[string]
  HE*[T] = Result[T, HailoError]

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc `$`*(status: hailo_status): string =
  let cmsg = hailo_get_status_message(status)
  result = $cmsg

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc `$`*(err: HailoError): string =
  result = &"HailoError: {err.status}: {err.msg}"

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc makeError*(status: hailo_status, msg: string): HailoError =
  result = HailoError(status: status, msg: msg)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc withTrace(err: HailoError, where: static[string]): HailoError {.inline.} =
  result = err
  #result.trace.add(where)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc trace*[T](res: HE[T], where: static[string]): HE[T] {.inline.} =
  if res.isErr:
    result = err(res.error.withTrace(where))
  else:
    result = res

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc errStatus*[T](res: HE[T]): hailo_status =
  if res.isErr:
    result = res.error.status
  else:
    result = HAILO_SUCCESS

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc errMsg*[T](res: HE[T]): string =
  if res.isErr:
    result = res.error.msg
  else:
    result = "No HailoError"

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc okVoid*(): HE[void] =
  ok()


when isMainModule:
  let stat = HAILO_SUCCESS
  echo $stat
