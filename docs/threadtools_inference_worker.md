# ThreadtoolsInferenceWorker and raw/custom output parsers

Date: 2026-06-14

This note describes how to use `hailort_nim` with non-YOLO HEFs, especially custom models whose output vstream is returned as a raw tensor / byte buffer.

## 1. Positioning

`ThreadtoolsDetectorWorker` is intended for YOLO / NMS-by-class models.

`ThreadtoolsInferenceWorker` is a generic worker where the output parser can be selected later.

```text
ThreadtoolsVStreamRunner
  HAILO input write / output read overlap

ThreadtoolsDetectorWorker
  YOLO / HAILO_NMS_BY_CLASS worker

ThreadtoolsInferenceWorker
  generic worker for raw tensor / text detection / custom parsers
```

For ordinary YOLO use, keep using `ThreadtoolsDetectorWorker`. For custom models, classification, segmentation, OCR, or text detection, start with `ThreadtoolsInferenceWorker` and the raw tensor parser, inspect the output, then add a model-specific parser.

## 2. Basic rule

`ThreadtoolsInferenceWorker` uses request/reply queues.

`waitReply(reply: var ThreadtoolsInferenceWorkerReply): HE[void]` writes into caller-owned storage. Only read `reply` when the returned result is OK.

```nim
var reply: ThreadtoolsInferenceWorkerReply
let rr = worker.waitReply(reply)
if rr.isErr:
  quit($rr.error)

case reply.kind
of tiwrResult:
  echo reply.result.requestId
of tiwrError:
  echo reply.error.message
```

This avoids returning large objects inside `Result[T,E]`, which could cause unwanted copies on hot paths.

## 3. Static metadata is not carried in replies

Cross-thread replies intentionally contain only the minimum payload.

```text
Contained in replies:
  requestId
  userData
  timings
  parser result payload

Not contained in replies:
  output vstream name
  network name
  static VStreamMetadata string fields
```

Static metadata should be read from the worker owner side.

```nim
let om = worker.outputMetadata()
echo om.name
```

This keeps cross-thread payloads small and avoids unnecessary ownership / destructor / move-hook complexity.

## 4. Raw tensor parser

For a new custom model, first use `hopRawTensor`.

```nim
let parserConfig = initRawTensorParserConfig(maxRawBytes = 0)

let worker = openThreadtoolsInferenceWorker(
  hefPath = "custom_model.hef",
  parserConfig = parserConfig,
  slotCount = 2,
  requestQueueSize = 4
).get()
```

`maxRawBytes = 0` means copy the whole output. Use a smaller value when you only need a preview.

Raw tensor output is returned as an owned payload.

```nim
let raw = reply.result.inference.raw

echo raw.bytes.len
for i in 0 ..< min(raw.bytes.len, 64):
  echo raw.bytes.byteAt(i)
```

Use `copyToSeq()` when a normal `seq[byte]` is needed.

```nim
let s = raw.bytes.copyToSeq()
```

## 5. Suggested raw output inspection flow

When receiving an unknown/custom HEF, first inspect:

1. input metadata
2. output metadata
3. output size
4. output type
5. output shape
6. raw preview / min / max / histogram

Use `examples/threadtools_inference_worker_raw_probe.nim`.

```sh
nim c -d:hailortThreadtools -d:release examples/threadtools_inference_worker_raw_probe.nim

./threadtools_inference_worker_raw_probe \
  custom_model.hef \
  input_960x544_rgb.raw \
  10 2 4 0 64 \
  custom_output.raw
```

The optional last argument dumps the last raw output payload to a file.

## 6. Visualizing raw output

If the output is a `UINT8` 1-channel score map with shape `544 x 960 x 1`:

```sh
ffmpeg -y \
  -f rawvideo \
  -pixel_format gray \
  -video_size 960x544 \
  -i custom_output.raw \
  custom_output.png
```

`video_size` is `width x height`. If HAILO metadata is `HxWxC = 544x960x1`, use `960x544`.

Value distribution check:

```sh
python3 - <<'PY'
p = "custom_output.raw"
b = open(p, "rb").read()
print("size =", len(b))
print("min  =", min(b))
print("max  =", max(b))
print(">0   =", sum(x > 0 for x in b))
print(">32  =", sum(x > 32 for x in b))
print(">64  =", sum(x > 64 for x in b))
print(">128 =", sum(x > 128 for x in b))
PY
```

## 7. Text detection parser

For models such as `paddle_ocr_v5_mobile_detection`, the output is a full-resolution `UINT8` score map with shape `544 x 960 x 1`.

`hopTextDetectionDb` converts this score map into `TextRegionResult` on the CPU.

The current implementation is a simple parser, not a full DBPostProcess clone.

```text
UINT8 score map
  threshold
  connected components
  min area / min width / min height filter
  bbox padding
  sort
  TextRegionResult
```

## 8. TextDetectionParserConfig

Main parameters:

```text
threshold:
  score-map binarization threshold

minArea:
  minimum connected-component area

minWidth / minHeight:
  minimum region size

padX / padY:
  bbox padding for easier crop/OCR input

maxRegions:
  maximum number of returned regions. 0 means unlimited

sortBy:
  top-left / score desc / area desc
```

A practical starting point for the synthetic test image was:

```text
threshold = 128
minArea   = 500
minWidth  = 8
minHeight = 4
padX      = 6
padY      = 8
maxRegions = 0
sortBy = top-left
```

## 9. Text detection probe

`examples/threadtools_text_detection_probe.nim` runs the text detection parser and writes a PPM overlay.

```sh
nim c -d:hailortThreadtools -d:release examples/threadtools_text_detection_probe.nim

./threadtools_text_detection_probe \
  paddle_ocr_v5_mobile_detection.hef \
  test_detection_960x544_rgb.raw \
  10 2 4 \
  128 500 8 4 \
  overlay.ppm \
  6 8 0
```

Convert the overlay to PNG:

```sh
ffmpeg -y -i overlay.ppm overlay.png
```

## 10. YOLO-like result conversion

`TextRegion` can be converted to the existing `Detection` type when a YOLO-like `score + bbox` representation is useful.

```nim
let det = region.toDetection(imageWidth = 960, imageHeight = 544, classId = 0)
let detections = result.regions.toDetections(imageWidth = 960, imageHeight = 544, classId = 0)
```

`classId = 0` can be treated as the `text` class.

Text detector bboxes usually represent text lines, not whole signs.

```text
OPEN 24 HOURS:
  OPEN
  24 HOURS

Wi-Fi Available:
  Wi-Fi
  Available
```

This is often the right unit for OCR recognition.

## 11. Adding a parser for a custom model

Suggested flow:

1. Dump raw output with `hopRawTensor`
2. Inspect metadata / shape / type / value range
3. Compare the output with the model specification or Python reference
4. Add a result type to `inference_result.nim`, or map to an existing result type
5. Add a parser module
6. Add a parser kind to `parseOutputInto()` in `inference_parser.nim`
7. Add a probe example for score / bbox / class output
8. Add overlay or raw dump support when useful

For float tensors, do not use the `UINT8` text detection parser. Confirm alignment, endianness, and HAILO output format before interpreting the raw byte buffer as `float32`.

## 12. Performance notes

Large raw outputs can make CPU-side postprocess expensive.

Text detection example:

```text
input  = 960 * 544 * 3 = 1,566,720 bytes
output = 960 * 544 * 1 =   522,240 bytes
```

Connected components over a full-resolution score map can cost several to tens of milliseconds on embedded CPUs.

Possible optimizations:

```text
reuse visited / queue buffers
reduce allocations
run-length connected components
early stop with maxRegions
scan only active pixels after thresholding
```

The first implementation should prioritize correctness and coordinate validation. Optimize after the output semantics are stable.
