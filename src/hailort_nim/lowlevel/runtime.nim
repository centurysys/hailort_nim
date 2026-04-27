import ./vdevice
import ../bindings/[c_api, types]
import ../internal/error

# ============================================================================
# Public types
# ============================================================================

type
  HailoRuntimeObj* = object
    ## Shared Hailo runtime context.
    ##
    ## This object owns a VDevice by default and is intended to be shared by
    ## multiple high-level model wrappers in later layers.
    vdevice*: Vdevice
    ownsVdevice*: bool

  HailoRuntime* = ref HailoRuntimeObj

# ============================================================================
# Lifetime management
# ============================================================================

# ----------------------------------------------------------------------------
#
# ----------------------------------------------------------------------------
proc `=destroy`(obj: var HailoRuntimeObj) =
  if obj.ownsVdevice and not obj.vdevice.isNil:
    discard obj.vdevice.close()
  obj.vdevice = nil
  obj.ownsVdevice = false

# ----------------------------------------------------------------------------
#
# ----------------------------------------------------------------------------
proc close*(runtime: HailoRuntime): HE[void] =
  if runtime.isNil:
    return okVoid()

  if runtime.ownsVdevice and not runtime.vdevice.isNil:
    let res = runtime.vdevice.close()
    if res.isErr:
      return res

  runtime.vdevice = nil
  runtime.ownsVdevice = false
  result = okVoid()

# ----------------------------------------------------------------------------
#
# ----------------------------------------------------------------------------
proc rawVdevice*(runtime: HailoRuntime): Vdevice {.inline.} =
  if runtime.isNil:
    return nil
  result = runtime.vdevice

# ----------------------------------------------------------------------------
#
# ----------------------------------------------------------------------------
proc isOpen*(runtime: HailoRuntime): bool {.inline.} =
  result = not runtime.isNil and not runtime.vdevice.isNil and
           not runtime.vdevice.rawHandle.isNil

# ============================================================================
# Opening shared runtime contexts
# ============================================================================

# ----------------------------------------------------------------------------
#
# ----------------------------------------------------------------------------
proc open*(
    _: typedesc[HailoRuntime],
    schedulingAlgorithm: SchedulingAlgorithm = HAILO_SCHEDULING_ALGORITHM_NONE
): HE[HailoRuntime] =
  ## Create a shared Hailo runtime context backed by one VDevice.
  ##
  ## High-level users should create this once and pass it to model wrappers
  ## that need to share the same physical Hailo device.
  var paramsRes = initVdeviceParams()
  if paramsRes.isErr:
    return paramsRes.error.err

  var params = paramsRes.get
  params.scheduling_algorithm = schedulingAlgorithm

  let vdevRes = createVdevice(params)
  if vdevRes.isErr:
    return vdevRes.error.err

  result = HailoRuntime(
    vdevice: vdevRes.get,
    ownsVdevice: true
  ).ok

# ----------------------------------------------------------------------------
#
# ----------------------------------------------------------------------------
proc wrap*(
    _: typedesc[HailoRuntime],
    vdevice: Vdevice,
    ownsVdevice = false
): HE[HailoRuntime] =
  ## Wrap an existing VDevice as a runtime context.
  ##
  ## This is useful for tests and for advanced code that already manages the
  ## VDevice lifetime explicitly.
  if vdevice.isNil or vdevice.rawHandle.isNil:
    return makeError(HAILO_INVALID_ARGUMENT, "vdevice is nil").err

  result = HailoRuntime(
    vdevice: vdevice,
    ownsVdevice: ownsVdevice
  ).ok
