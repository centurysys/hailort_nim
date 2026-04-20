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
    flags*: set[FormatFlag]
    shape*: ImageShape
