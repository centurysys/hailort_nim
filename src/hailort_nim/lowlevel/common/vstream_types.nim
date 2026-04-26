type
  TensorDataType* = enum
    tdtUnknown
    tdtAuto
    tdtUint8
    tdtUint16
    tdtFloat32
  PixelFormat* = enum
    pfUnknown
    pfAuto
    pfNhwc
    pfNhcw
    pfNchw
    pfNhw
    pfNc
    pfRgb888
    pfRgb4
    pfNv12
    pfNv21
    pfYuy2
    pfI420
    pfFcr
    pfF8cr
    pfBayerRgb
    pf12BitBayerRgb
    pfHailoNms
    pfHailoNmsWithByteMask
    pfHailoNmsOnChip
    pfHailoNmsByClass
    pfHailoNmsByScore
    pfHailoYyuv
    pfHailoYyvu
    pfHailoYyyyuv
  # Logical image type (derived)
  ImageType* = enum
    itUnknown
    itNhwc3
    itNhwc4
    itNv12
    itNv21
    itYuy2
    itI420
  ImageShape* = object
    height*: int
    width*: int
    channels*: int
  FormatFlag* = enum
    ffNone
    ffQuantized
    ffTransposed
  VStreamMetadata* = object
    name*: string
    networkName*: string
    dataType*: TensorDataType
    pixelFormat*: PixelFormat
    imageType*: ImageType
    flags*: set[FormatFlag]
    shape*: ImageShape

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc `$`*(t: ImageType): string =
  case t
  of itNhwc3: "NHWC3"
  of itNhwc4: "NHWC4"
  of itNv12: "NV12"
  of itNv21: "NV21"
  of itYuy2: "YUY2"
  of itI420: "I420"
  else: "UNKNOWN"

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc `$`*(t: TensorDataType): string =
  case t
  of tdtAuto:
    "AUTO"
  of tdtUint8:
    "UINT8"
  of tdtUint16:
    "UINT16"
  of tdtFloat32:
    "FLOAT32"
  else:
    "UNKNOWN"

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc `$`*(p: PixelFormat): string =
  case p
  of pfNhwc: "NHWC"
  of pfRgb888: "RGB888"
  of pfRgb4: "RGB4"
  of pfNv12: "NV12"
  of pfNv21: "NV21"
  of pfYuy2: "YUY2"
  of pfI420: "I420"
  of pfHailoNmsByClass: "HAILO_NMS_BY_CLASS"
  else: "UNKNOWN"
