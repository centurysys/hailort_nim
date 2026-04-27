import std/[os, strutils, strformat, monotimes, times]

import hailort_nim
import ./common/common

# ------------------------------------------------------------------------------
# File helpers:
# ------------------------------------------------------------------------------
proc readFileBytes(path: string): seq[byte] =
  let s = readFile(path)
  result = newSeq[byte](s.len)
  if s.len > 0:
    copyMem(addr result[0], unsafeAddr s[0], s.len)

# ------------------------------------------------------------------------------
# Debug helpers:
# ------------------------------------------------------------------------------
proc checksum(data: openArray[byte]): uint64 =
  ## Small checksum for checking that the output buffer was actually written.
  ## This is not intended to be cryptographic.
  result = 1469598103934665603'u64
  for b in data:
    result = result xor uint64(b)
    result = result * 1099511628211'u64

proc bufferAddress(data: var openArray[byte]): string =
  if data.len == 0:
    return "nil"
  result = "0x" & cast[uint](addr data[0]).toHex()

proc printInputMetadata(det: Detector) =
  let md = getOrFail(det.inputMetadata(), "Detector.inputMetadata")
  echo "Input metadata:"
  echo &"  name       : {md.name}"
  echo &"  network    : {md.networkName}"
  echo &"  type       : {md.dataType}"
  echo &"  order      : {md.pixelFormat}"
  echo &"  image_type : {md.imageType}"
  echo &"  flags      : {md.flags}"
  echo &"  shape      : {md.shape}"
  echo &"  frame_size : {det.inputSize()}"

proc printOutputMetadata(det: Detector) =
  let md = getOrFail(det.outputMetadata(), "Detector.outputMetadata")
  echo "Output metadata:"
  echo &"  name       : {md.name}"
  echo &"  network    : {md.networkName}"
  echo &"  type       : {md.dataType}"
  echo &"  order      : {md.pixelFormat}"
  echo &"  image_type : {md.imageType}"
  echo &"  flags      : {md.flags}"
  echo &"  shape      : {md.shape}"
  echo &"  frame_size : {det.outputSize()}"

# ------------------------------------------------------------------------------
# Test helpers:
# ------------------------------------------------------------------------------
proc runInferInto(det: Detector; input: openArray[byte]; output: var seq[byte];
    loops: int; warmup: int) =
  echo ""
  echo "== inferInto buffer reuse test =="
  echo &"output buffer len  : {output.len}"
  echo &"output buffer addr : {bufferAddress(output)}"

  for i in 0 ..< warmup:
    let t0 = getMonoTime()
    checkOrFail(det.inferInto(input, output), "Detector.inferInto warmup")
    let elapsed = getMonoTime() - t0
    echo &"Warmup[{i:>2}] : {elapsed.inMicroseconds.float / 1000.0:>8.3f} ms checksum=0x{checksum(output).toHex()}"

  var totalMs = 0.0
  var minMs = 1.0e18
  var maxMs = 0.0

  for i in 0 ..< loops:
    let beforeAddr = bufferAddress(output)
    let t0 = getMonoTime()
    checkOrFail(det.inferInto(input, output), "Detector.inferInto")
    let elapsed = getMonoTime() - t0
    let afterAddr = bufferAddress(output)

    if beforeAddr != afterAddr:
      echo &"ERROR: output buffer address changed: before={beforeAddr} after={afterAddr}"
      quit(QuitFailure)

    let ms = elapsed.inMicroseconds.float / 1000.0
    if ms < minMs:
      minMs = ms
    if ms > maxMs:
      maxMs = ms
    totalMs += ms

    echo &"Loop[{i:>2}] : {ms:>8.3f} ms checksum=0x{checksum(output).toHex()} addr={afterAddr}"

  let avgMs = totalMs / loops.float
  let fps = if avgMs > 0.0: 1000.0 / avgMs else: 0.0

  echo ""
  echo "Timing summary:"
  echo &"  total      : {totalMs:.3f} ms"
  echo &"  average    : {avgMs:.3f} ms"
  echo &"  min        : {minMs:.3f} ms"
  echo &"  max        : {maxMs:.3f} ms"
  echo &"  approx fps : {fps:.2f}"

proc runDirectInto(det: Detector; input: openArray[byte]; output: var seq[byte]) =
  echo ""
  echo "== direct Into API smoke test =="

  let inputImageType = getOrFail(det.inputImageType(), "Detector.inputImageType")

  case inputImageType
  of itNhwc4:
    checkOrFail(det.inferNhwc4Into(input, output), "Detector.inferNhwc4Into")
    echo &"inferNhwc4Into : ok checksum=0x{checksum(output).toHex()}"
  else:
    checkOrFail(det.inferRawInto(input, output), "Detector.inferRawInto")
    echo &"inferRawInto   : ok checksum=0x{checksum(output).toHex()}"

proc runWrapperCompatibilityCheck(det: Detector; input: openArray[byte];
    output: var seq[byte]) =
  echo ""
  echo "== wrapper compatibility check =="

  checkOrFail(det.inferInto(input, output), "Detector.inferInto")
  let intoChecksum = checksum(output)

  let wrapped = getOrFail(det.infer(input), "Detector.infer")
  let wrappedChecksum = checksum(wrapped)

  echo &"inferInto checksum : 0x{intoChecksum.toHex()}"
  echo &"infer     checksum : 0x{wrappedChecksum.toHex()}"

  if wrapped.len != output.len:
    echo &"ERROR: output length mismatch: inferInto={output.len} infer={wrapped.len}"
    quit(QuitFailure)

  if wrapped != output:
    echo "ERROR: inferInto output does not match infer output"
    quit(QuitFailure)

  echo "wrapper compatibility: ok"

# ------------------------------------------------------------------------------
# CLI:
# ------------------------------------------------------------------------------
proc printUsage() =
  echo "Usage: infer_into <hef> <raw_input> [loops] [warmup] [hailo_nms_score_threshold] [check_wrapper]"
  echo ""
  echo "Examples:"
  echo "  infer_into yolov11s.hef dog_640x640x3.raw 20 5"
  echo "  infer_into yolov11s_RGBX.hef frame_1920x1080x4.raw 20 5"
  echo "  infer_into yolov11s.hef dog_640x640x3.raw 20 5 0.20 true"

when isMainModule:
  proc main() =
    if paramCount() < 2:
      printUsage()
      quit(QuitFailure)

    let hefPath = paramStr(1)
    let rawPath = paramStr(2)
    let loops = if paramCount() >= 3: parseInt(paramStr(3)) else: 20
    let warmup = if paramCount() >= 4: parseInt(paramStr(4)) else: 5
    let hailoNmsScoreThreshold =
      if paramCount() >= 5: parseFloat(paramStr(5)).float32 else: 0.20'f32
    let checkWrapper =
      if paramCount() >= 6: parseBool(paramStr(6)) else: false

    let input = readFileBytes(rawPath)

    let openStart = getMonoTime()
    var det = getOrFail(
      Detector.open(hefPath, hailoNmsScoreThreshold = hailoNmsScoreThreshold),
      "Detector.open"
    )
    let openElapsed = getMonoTime() - openStart
    defer:
      discard det.close()

    printInputMetadata(det)
    printOutputMetadata(det)
    echo &"Open time : {openElapsed.inMicroseconds.float / 1000.0:.3f} ms"
    echo &"Input len : {input.len}"
    echo &"Loops     : {loops}"
    echo &"Warmup    : {warmup}"

    var output = newSeq[byte](det.outputSize())

    runDirectInto(det, input, output)
    runInferInto(det, input, output, loops, warmup)

    if checkWrapper:
      runWrapperCompatibilityCheck(det, input, output)

  main()
