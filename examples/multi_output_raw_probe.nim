when not compileOption("threads"):
  {.warning: "This probe does not require --threads:on, but it is usually built with the same flags as threadtools probes.".}

import std/[math, os, strformat, strutils, monotimes, times]

import hailort_nim

proc elapsedMs(started: MonoTime): float =
  result = float(inMicroseconds(getMonoTime() - started)) / 1000.0

proc usage() =
  echo "Usage: multi_output_raw_probe <model.hef> <input.raw> [loops=1] [preview=64] [dump_prefix] [output_format=auto]"
  echo ""
  echo "output_format: auto | uint8 | uint16 | float32"
  echo ""
  echo "Examples:"
  echo "  ./multi_output_raw_probe yolov8s_pose.hef pose_test_640x640_rgb.raw"
  echo "  ./multi_output_raw_probe yolov8s_pose.hef pose_test_640x640_rgb.raw 10 128 pose_out"
  echo "  ./multi_output_raw_probe yolov8s_pose.hef pose_test_640x640_rgb.raw 10 128 pose_out float32"
  echo "  ./multi_output_raw_probe yolov8s_pose.hef pose_test_640x640_rgb.raw 10 128 float32"

proc readFileBytes(path: string): seq[byte] =
  let data = readFile(path)
  result = newSeq[byte](data.len)
  if data.len > 0:
    copyMem(addr result[0], unsafeAddr data[0], data.len)

proc writeFileBytes(path: string; data: openArray[byte]) =
  var f = open(path, fmWrite)
  defer: f.close()
  if data.len > 0:
    discard f.writeBuffer(unsafeAddr data[0], data.len)

proc previewBytes(data: openArray[byte]; maxCount: int): string =
  let n = min(data.len, max(0, maxCount))
  var parts = newSeq[string](n)
  for i in 0 ..< n:
    parts[i] = toHex(data[i], 2)
  result = parts.join(" ")

proc readFloat32LE(data: openArray[byte]; index: int): float32 =
  let pos = index * sizeof(float32)
  if pos < 0 or pos + sizeof(float32) > data.len:
    return 0.0'f32

  copyMem(addr result, unsafeAddr data[pos], sizeof(float32))

proc previewFloat32(data: openArray[byte]; maxCount: int): string =
  let count = min(data.len div sizeof(float32), max(0, maxCount))
  var parts = newSeq[string](count)
  for i in 0 ..< count:
    let v = readFloat32LE(data, i)
    parts[i] = &"{v:.6g}"
  result = parts.join(" ")

type
  Float32Stats = object
    count: int
    finiteCount: int
    nanCount: int
    posInfCount: int
    negInfCount: int
    zeroCount: int
    nonZeroCount: int
    minValue: float32
    maxValue: float32
    meanValue: float64

proc computeFloat32Stats(data: openArray[byte]): Float32Stats =
  result.count = data.len div sizeof(float32)
  if result.count <= 0:
    return

  var initialized = false
  var sum = 0.0

  for i in 0 ..< result.count:
    let v = readFloat32LE(data, i)
    if classify(v) == fcNan:
      inc result.nanCount
      continue
    if classify(v) == fcInf:
      inc result.posInfCount
      continue
    if classify(v) == fcNegInf:
      inc result.negInfCount
      continue

    inc result.finiteCount
    if v == 0.0'f32:
      inc result.zeroCount
    else:
      inc result.nonZeroCount

    if not initialized:
      result.minValue = v
      result.maxValue = v
      initialized = true
    else:
      if v < result.minValue:
        result.minValue = v
      if v > result.maxValue:
        result.maxValue = v

    sum += float(v)

  if result.finiteCount > 0:
    result.meanValue = sum / float(result.finiteCount)

proc isFormatName(s: string): bool =
  case s.normalize()
  of "auto", "uint8", "u8", "uint16", "u16", "float32", "f32":
    true
  else:
    false

proc parseFormatType(s: string): hailo_format_type_t =
  case s.normalize()
  of "auto":
    HAILO_FORMAT_TYPE_AUTO
  of "uint8", "u8":
    HAILO_FORMAT_TYPE_UINT8
  of "uint16", "u16":
    HAILO_FORMAT_TYPE_UINT16
  of "float32", "f32":
    HAILO_FORMAT_TYPE_FLOAT32
  else:
    raise newException(ValueError, &"unsupported output_format: {s}")

proc printFormat(prefix: string; fmt: Format) =
  echo prefix
  echo &"  order       : {pixelFormatName(pixelFormat(fmt))}"
  echo &"  type        : {dataTypeName(tensorDataType(fmt))}"
  echo &"  flags       : {formatFlags(fmt)}"

proc printMetadata(prefix: string; md: VStreamMetadata; size = -1) =
  echo prefix
  echo &"  name        : {md.name}"
  echo &"  network     : {md.networkName}"
  echo &"  type        : {dataTypeName(md.dataType)}"
  echo &"  pixelFormat : {pixelFormatName(md.pixelFormat)}"
  echo &"  imageType   : {md.imageType}"
  echo &"  flags       : {md.flags}"
  echo &"  shape       : {md.shape}"
  if size >= 0:
    echo &"  frame_size  : {size}"

when isMainModule:
  if paramCount() < 2:
    usage()
    quit 1

  let hefPath = paramStr(1)
  let rawPath = paramStr(2)
  let loops = if paramCount() >= 3: parseInt(paramStr(3)) else: 1
  let previewCount = if paramCount() >= 4: parseInt(paramStr(4)) else: 64

  var dumpPrefix = ""
  var outputFormatText = "auto"

  if paramCount() >= 5:
    let p5 = paramStr(5)
    if isFormatName(p5) and paramCount() == 5:
      outputFormatText = p5
    else:
      dumpPrefix = p5

  if paramCount() >= 6:
    outputFormatText = paramStr(6)

  let outputFormatType =
    try:
      parseFormatType(outputFormatText)
    except ValueError as e:
      echo e.msg
      usage()
      quit 1

  if loops <= 0:
    echo "loops must be positive"
    quit 1

  let input = readFileBytes(rawPath)

  echo &"hef={hefPath}"
  echo &"raw={rawPath}"
  echo &"input_file_size={input.len}"
  echo &"loops={loops} preview={previewCount}"
  echo &"output_format={formatTypeName(outputFormatType)}"
  if dumpPrefix.len > 0:
    echo &"dump_prefix={dumpPrefix}"
  echo ""

  let modelRes = MultiOutputInference.open(
    hefPath,
    profiling = true,
    outputFormatType = outputFormatType
  )
  if modelRes.isErr:
    echo "MultiOutputInference.open failed: ", modelRes.error
    quit 1

  let model = modelRes.get

  let inputMdRes = model.inputMetadata()
  if inputMdRes.isErr:
    echo "inputMetadata failed: ", inputMdRes.error
    discard model.close()
    quit 1

  printMetadata("Input metadata:", inputMdRes.get, model.inputSize())
  echo ""

  echo &"Output vstreams: {model.outputCount()}"
  echo &"Requested output format: {model.requestedOutputFormatName()}"

  let outputMetasRes = model.outputMetadatas()
  if outputMetasRes.isErr:
    echo "outputMetadatas failed: ", outputMetasRes.error
    discard model.close()
    quit 1

  let outputFormatsRes = model.outputUserFormats()
  if outputFormatsRes.isErr:
    echo "outputUserFormats failed: ", outputFormatsRes.error
    discard model.close()
    quit 1

  let outputMetas = outputMetasRes.get
  let outputFormats = outputFormatsRes.get
  for i, md in outputMetas:
    printMetadata(&"Output[{i}] metadata:", md, model.outputSize(i))
    if i < outputFormats.len:
      printFormat(&"Output[{i}] user format:", outputFormats[i])
  echo ""

  if input.len != model.inputSize():
    echo &"input size mismatch: expected={model.inputSize()} actual={input.len}"
    discard model.close()
    quit 1

  var last: MultiOutputInferenceResult
  let started = getMonoTime()
  for i in 0 ..< loops:
    let res = model.inferRaw(input)
    if res.isErr:
      echo "inferRaw failed: ", res.error
      discard model.close()
      quit 1
    last = res.get

  let elapsed = elapsedMs(started)
  let fps = float(loops) * 1000.0 / elapsed

  echo "Multi-output raw summary:"
  echo &"  elapsed    : {elapsed:.3f} ms"
  echo &"  fps        : {fps:.2f}"
  echo &"  avg write  : {float(model.profile.writeUs) / float(loops) / 1000.0:.3f} ms"
  echo &"  avg read   : {float(model.profile.readUs) / float(loops) / 1000.0:.3f} ms"
  echo &"  outputs    : {last.outputs.len}"

  for item in last.outputs:
    let idx = item.index
    let md = if idx >= 0 and idx < outputMetas.len: outputMetas[idx] else: VStreamMetadata()
    let fmt = if idx >= 0 and idx < outputFormats.len: outputFormats[idx] else: Format()
    let dataType = tensorDataType(fmt)
    let dumpPath = if dumpPrefix.len > 0: &"{dumpPrefix}_output{idx:02d}.raw" else: ""

    echo &"  output[{idx}] name={md.name} size={item.data.len} read={float(item.readUs) / 1000.0:.3f} ms user_type={dataTypeName(dataType)}"
    echo &"    preview: {previewBytes(item.data, previewCount)}"

    if dataType == tdtFloat32:
      let floatPreviewCount = min(previewCount, 32)
      let stats = computeFloat32Stats(item.data)
      echo &"    float_preview: {previewFloat32(item.data, floatPreviewCount)}"
      echo &"    float_stats  : count={stats.count} finite={stats.finiteCount} min={stats.minValue:.6g} max={stats.maxValue:.6g} mean={stats.meanValue:.6g} zero={stats.zeroCount} nonzero={stats.nonZeroCount} nan={stats.nanCount} +inf={stats.posInfCount} -inf={stats.negInfCount}"

    if dumpPath.len > 0:
      writeFileBytes(dumpPath, item.data)
      echo &"    dumped : {dumpPath}"

  let closeRes = model.close()
  if closeRes.isErr:
    echo "close failed: ", closeRes.error
    quit 1
