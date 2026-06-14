# hailort_nim

`hailort_nim` is a Nim binding and high-level helper library for HailoRT.

It provides low-level access to the HailoRT C API and higher-level APIs for running inference on HAILO-8 / HAILO-8L devices from Nim applications.

The high-level API covers YOLO-style object detection models that output `HAILO_FORMAT_ORDER_HAILO_NMS_BY_CLASS`, raw/custom single-output models, and selected multi-output models such as YOLOv8 pose.

## ✨ Features

- Low-level Nim bindings for HailoRT
- High-level `Detector` API for YOLO / NMS-by-class models
- Explicit open / activate / deactivate / close lifecycle control
- Multi-HEF preparation and fast model switching
- Optional inference profiling for the high-level `Detector`
- Optional `threadtools`-based detector runner for streaming / pipeline-style applications
- Worker-style submit / receive API with request correlation metadata
- Pooled input submission using `threadtools` pool items for pipeline-style ownership transfer
- Generic `ThreadtoolsInferenceWorker` for raw tensor / custom single-output model outputs
- `MultiOutputInference` for HEFs with multiple output vstreams
- `ThreadtoolsMultiOutputInferenceWorker` for multi-output worker pipelines
- Simple text detection parser for UINT8 score-map outputs
- YOLOv8 pose parser for bbox + 17-keypoint pose results
- Embedded / edge-device oriented design

## ⚠️ Important usage rule

Do not repeatedly open and close a HEF in a frame loop.

Bad:

```nim
for frame in frames:
  let det = Detector.open("yolov11n.hef").get()
  let detections = det.detectNmsByClassAuto(frame).get()
  discard det.close()
```

This is inefficient and can eventually lead to HailoRT resource pressure.

Open once, then reuse:

```nim
let det = Detector.open("yolov11n.hef").get()
defer:
  discard det.close()

for frame in frames:
  let detections = det.detectNmsByClassAuto(frame).get()
```

For multiple models, prepare once and switch by activation.

## 🚀 Quick start

```nim
import hailort_nim

let detector = Detector.open("yolov11n.hef").get()
defer:
  discard detector.close()

let input: seq[byte] = readFile("dog_640x640x3.raw").toOpenArrayByteSeq()
let detections = detector.detectNmsByClassAuto(input).get()

for det in detections:
  echo det
```

The input buffer must match the input vstream format and frame size expected by the HEF.

For many YOLO HEFs this is a 640 x 640 RGB byte buffer, but the exact requirement depends on the compiled HEF. Use the metadata helpers or `hailortcli parse-hef` to confirm the expected input format.

## 🔍 Detector API

The synchronous `Detector` API is the simplest entry point.

```nim
let detector = Detector.open("yolov11n.hef").get()
let detections = detector.detectNmsByClassAuto(input).get()
```

For performance-sensitive loops, prefer APIs that reuse caller-provided output containers and buffers where available.

```nim
var outputBuf = newSeq[byte](detector.outputSize())
var detections: seq[Detection] = @[]

discard detector.detectNmsByClassAutoInto(
  input,
  outputBuf,
  detections,
  appScoreThreshold = 0.25'f32
)
```

## 🔁 Multi-model usage

Loading or configuring HEFs repeatedly is expensive. For applications that need to switch between several HEFs, use the prepared model flow.

Concept:

```text
open runtime once
prepare models once
activate model A
infer
deactivate model A
activate model B
infer
deactivate model B
```

Example:

```nim
let runtime = HailoRuntime.open().get()

let detA = Detector.openPrepared(runtime, "model_a.hef").get()
let detB = Detector.openPrepared(runtime, "model_b.hef").get()

discard detA.activate()
discard detA.detectNmsByClassAuto(inputA)
discard detA.deactivate()

discard detB.activate()
discard detB.detectNmsByClassAuto(inputB)
discard detB.deactivate()
```

This avoids repeated HEF open / close cycles and keeps model switching as a lightweight runtime operation.

## ⏱️ Detector profiling

`Detector` can optionally collect per-stage timing information.

Profiling can be enabled when opening:

```nim
let detector = Detector.open("yolov11n.hef", profiling = true).get()
```

Or enabled later:

```nim
detector.enableProfiling()
```

After running inference:

```nim
echo detector.profileSummary()
detector.resetProfile()
```

The profiled stages include:

- input validation
- input vstream write
- output vstream read
- NMS output parsing
- detection sorting

This is useful for checking whether time is spent in host-side code, HailoRT transfer, or device execution wait.

## 🧵 Threadtools detector support

`hailort_nim` includes optional `threadtools` integration for applications that continuously feed frames or tensors into HAILO from worker-based pipelines.

The goal is to keep HAILO busy while avoiding an `asyncdispatch`-centric API around blocking HailoRT vstream reads.

The threadtools path provides several levels:

```text
ThreadtoolsVStreamRunner:
  model-agnostic vstream write/read overlap
  caller submits input buffers
  internal read worker waits for output vstream results

ThreadtoolsDetector:
  ThreadtoolsVStreamRunner + YOLO NMS-by-class parsing
  caller submits input buffers and receives parsed detections

ThreadtoolsDetectorWorker:
  request queue + reply queue + detector worker thread
  suitable for single-output YOLO application / codec pipeline integration

ThreadtoolsInferenceWorker:
  request queue + reply queue for raw tensor / text detection / custom single-output parsers

ThreadtoolsMultiOutputInferenceWorker:
  request queue + reply queue for multi-output HEFs
  currently supports YOLOv8 pose decoding
```

### Build requirements

Enable the threadtools path with `-d:hailortThreadtools`.

```bash
nim c -d:hailortThreadtools -d:release examples/threadtools_detector_worker_probe.nim
```

Recent Nim 2.x environments may enable threads by default. If your configuration does not, add `--threads:on`.

The threadtools path depends on the `threadtools` and `move_results` packages being visible to Nimble or Nim's module search path.

### ThreadtoolsDetector

`ThreadtoolsDetector` is useful when the caller wants direct control over submit / receive order while keeping the blocking output read on the internal vstream read worker.

```nim
let det = Detector.open("yolov11s.hef").get()
defer:
  discard det.close()

let tdet = det.openThreadtoolsDetector(slotCount = 2, appScoreThreshold = 0.25'f32).get()
defer:
  discard tdet.close()

discard tdet.submit(input)

var detections: seq[Detection] = @[]
let r = tdet.waitDetections(detections)
if r.isErr:
  quit($r.error)
```

The output slot is released internally after parsing, so callers do not need to handle vstream output pointer lifetime directly in this path.

### ThreadtoolsDetectorWorker

`ThreadtoolsDetectorWorker` is the preferred API for pipeline-style applications.

It owns a detector worker thread and exposes a queue-oriented interface:

```nim
let worker = openThreadtoolsDetectorWorker(
  "yolov11s.hef",
  slotCount = 2,
  requestQueueSize = recommendedThreadtoolsDetectorWorkerRequestQueueSize(2),
  appScoreThreshold = 0.25'f32
).get()

discard worker.submitCopy(
  requestId = 0'u64,
  input = input,
  userData = 10000'u64
)

var reply: ThreadtoolsDetectorWorkerReply
let rr = worker.waitReply(reply)
if rr.isErr:
  quit($rr.error)

echo reply.requestId
for det in reply.detections:
  echo det

discard worker.stop()
discard worker.join()
```

For pipeline usage, prefer `submit()` with a moved `seq[byte]` when the input buffer ownership can be transferred to the worker.

Use `submitCopy()` as a convenience API when the caller owns an `openArray[byte]` or wants to keep the original buffer.

For streaming pipelines where input tensors are already managed by a `threadtools` pool, use `submitPooled()` / `submitPoolItem()`:

```nim
let pool = newPool[seq[byte]](requestQueueSize).get()

# Fill the pool with input buffers elsewhere.
var item = pool.acquire()

discard worker.submitPooled(
  move item,
  requestId = frameId,
  appScoreThreshold = 0.25'f32,
  userData = cameraFrameKey
)
```

The worker performs the HAILO input vstream write synchronously, then the pooled input item is returned to its original pool automatically when the request leaves the worker path. This is the preferred ownership-transfer API for codec / frame pipelines.

### Request correlation

Worker requests and replies carry two correlation fields:

```text
requestId:
  sequential or application-defined request identifier

userData:
  opaque uint64 for application metadata
```

This allows applications to associate results with camera, frame, event, or timestamp identifiers without relying only on receive order.

Error replies preserve the same metadata so failed requests can also be traced.

### Queue depth

For `slotCount = 2`, use a request queue size of at least 4.

A queue depth equal to the slot count can underfill the worker pipeline and leave the HAILO vstream path idle between replies.

Use:

```nim
let qsize = recommendedThreadtoolsDetectorWorkerRequestQueueSize(slotCount)
```

Current testing on TI AM67A (4x Cortex-A53 at 1.4 GHz) with HAILO-8L and YOLOv11s showed that increasing the request queue beyond `slotCount * 2` did not improve throughput, but it can still be useful if the application intentionally wants more input buffering.

### Shutdown

The worker supports explicit graceful shutdown:

```nim
discard worker.stop()
discard worker.join()
```

`close()` is a convenience wrapper for stop plus join.

`stop()` is graceful: already-submitted requests are drained before the worker exits. New submissions are rejected after stopping begins.


## 🧩 Generic inference / raw output support

For models that do not produce HAILO NMS-by-class output, use `ThreadtoolsInferenceWorker`.

This worker is intended for custom models, text detection, OCR, classification, segmentation, or any HEF whose output needs application-specific CPU post-processing.  Start with the raw tensor parser, inspect the output metadata and byte buffer, then add a parser for the model-specific output format.

```text
ThreadtoolsDetectorWorker:
  YOLO / HAILO_NMS_BY_CLASS parsed detections

ThreadtoolsInferenceWorker:
  raw tensor / text detection / custom parser result
```

The raw tensor path returns an owned output payload through the reply queue. Static output metadata such as vstream name, network name, shape, and format should be read from the worker owner side instead of being embedded in each cross-thread reply.

```nim
let parserConfig = initRawTensorParserConfig(maxRawBytes = 0)
let worker = openThreadtoolsInferenceWorker(
  hefPath = "custom_model.hef",
  parserConfig = parserConfig,
  slotCount = 2,
  requestQueueSize = 4
).get()

let outputMeta = worker.outputMetadata()
echo outputMeta.name
```

See `docs/threadtools_inference_worker.md` for details on raw output inspection, custom parser flow, and thread-safe reply ownership rules.


## 🧍 YOLOv8 pose multi-output support

`hailort_nim` includes a reusable YOLOv8 pose parser and a threadtools worker path for multi-output pose HEFs such as `yolov8s_pose`.

Unlike NMS-by-class YOLO object detection HEFs, `yolov8s_pose` exposes multiple output vstreams. The tested HAILO-8L model has three output groups, one per grid scale. Each group contains:

```text
bbox regression: H x W x 64   # YOLOv8 DFL logits, 4 sides * 16 bins
person score   : H x W x 1
keypoints      : H x W x 51   # 17 keypoints * (x, y, score/logit)
```

The HAILO runtime returns tensors; the library-side parser performs the CPU postprocess:

```text
FLOAT32 multi-output tensors
  ↓ group bbox / score / keypoint heads by grid size
  ↓ decode YOLOv8 DFL bbox regression
  ↓ decode 17 COCO keypoints
  ↓ score threshold
  ↓ bbox IoU NMS
PoseResult
```

Main result types:

```text
PoseResult
  poses: seq[PoseDetection]

PoseDetection
  bbox
  score
  center
  sourceScale / cellX / cellY
  keypoints[17]

PoseKeypoint
  x / y / score
```

`PoseDetection` can also be converted to the existing normalized `Detection` type when a bbox-only YOLO-like view is needed. Keypoint data is intentionally dropped in that compatibility conversion.

Use `ThreadtoolsMultiOutputInferenceWorker` when the model has multiple output vstreams. `ThreadtoolsDetectorWorker` remains the simple path for single-output NMS-by-class YOLO object detection.

See `docs/threadtools_multi_output_inference_worker.md` for API details and ownership rules.

## 🔤 Text detection parser

`hailort_nim` also includes an initial CPU-side text detection parser for models such as `paddle_ocr_v5_mobile_detection`.

That model returns a full-resolution `UINT8` score map, for example `544 x 960 x 1`. The parser thresholds the score map, runs connected components, filters small regions, pads bboxes, and returns a `TextRegionResult`.

The result can also be converted to the existing YOLO-like `Detection` representation when the application wants `score + bbox` results.

```text
HAILO output score map
  ↓ CPU parser
TextRegionResult
  ↓ optional conversion
seq[Detection] with classId = text
```

This parser is intentionally simple and is not a full DBPostProcess implementation yet. It is useful for validating output semantics, coordinates, and crop regions before adding OCR recognizer integration.

## 🧪 Examples

### ▶️ Synchronous inference

```bash
nim c -d:release examples/infer_high.nim
./examples/infer_high yolov11n.hef dog_640x640x3.raw
```

### ⏱️ Profiling example

```bash
nim c -d:release examples/infer_high_profile.nim
./examples/infer_high_profile yolov11n.hef dog_640x640x3.raw 50 5
```

### 🧵 Threadtools detector probe

```bash
nim c -d:hailortThreadtools -d:release examples/threadtools_detector_probe.nim
./examples/threadtools_detector_probe yolov11s.hef dog.raw 100 2 0.25
```

### 🧵 Threadtools detector worker probe

```bash
nim c -d:hailortThreadtools -d:release examples/threadtools_detector_worker_probe.nim
./examples/threadtools_detector_worker_probe yolov11s.hef dog.raw 100 2 4 0.25
```

### 🧵 Threadtools detector worker pooled-input probe

```bash
nim c -d:hailortThreadtools -d:release examples/threadtools_detector_worker_pooled_probe.nim
./examples/threadtools_detector_worker_pooled_probe yolov11s.hef dog.raw 100 2 4 0.25
```

This probe pre-fills a `threadtools` pool with input tensors and submits pool items to the worker. It is closer to the intended codec pipeline ownership model than repeatedly copying borrowed input arrays.


### 🧩 Threadtools raw tensor probe

```bash
nim c -d:hailortThreadtools -d:release examples/threadtools_inference_worker_raw_probe.nim
./examples/threadtools_inference_worker_raw_probe custom_model.hef input.raw 10 2 4 0 64 custom_output.raw
```

The optional last argument writes the last raw output payload to a file for offline inspection.

### 🔤 Threadtools text detection probe

```bash
nim c -d:hailortThreadtools -d:release examples/threadtools_text_detection_probe.nim
./examples/threadtools_text_detection_probe paddle_ocr_v5_mobile_detection.hef test_detection_960x544_rgb.raw 10 2 4 128 500 8 4 overlay.ppm 6 8 0
```

Convert the overlay to PNG if needed:

```bash
ffmpeg -y -i overlay.ppm overlay.png
```


### 🧍 Multi-output YOLOv8 pose probe

```bash
nim c -d:release examples/multi_output_yolov8_pose_probe.nim
./examples/multi_output_yolov8_pose_probe yolov8s_pose.hef pose_test_640x640_rgb.raw 0.25 100 pose_overlay.ppm 0.5 0.45 20
```

This synchronous probe uses `MultiOutputInference`, requests FLOAT32 output tensors, decodes YOLOv8 pose results, prints bbox/keypoint data, and writes a PPM overlay.

### 🧵 Threadtools YOLOv8 pose worker probe

```bash
nim c -d:hailortThreadtools -d:release examples/threadtools_yolov8_pose_probe.nim
./examples/threadtools_yolov8_pose_probe yolov8s_pose.hef pose_test_640x640_rgb.raw 10 0.25 100 pose_worker_overlay.ppm 0.5 0.45 20
```

Convert the overlay to PNG if needed:

```bash
ffmpeg -y -i pose_worker_overlay.ppm pose_worker_overlay.png
```

## 📈 Throughput notes

On TI AM67A (4x Cortex-A53 at 1.4 GHz) with HAILO-8L and a YOLOv11s HEF, both the normal worker path and the pooled-input worker path reached about 39.5 fps with two in-flight slots:

```text
loops      : 100
slots      : 2
queue      : 4
fps        : 39.5
avg write  : about 3.1 ms
avg read   : about 25.2 ms
avg parse  : about 0.01 ms
```

A practical starting point is:

```nim
let slotCount = 2
let requestQueueSize = recommendedThreadtoolsDetectorWorkerRequestQueueSize(slotCount)
```



YOLOv8 pose on the same board with HAILO-8L and a multi-output `yolov8s_pose` HEF reached about 37 fps in release builds when repeatedly processing a pre-resized 640 x 640 RGB input:

```text
loops          : 10
poses          : 3 on a three-person test image
avg write      : about 1.2 ms
avg read       : about 22 ms
avg parse      : about 0.8 ms
profile total  : about 26.7 ms
fps            : about 37.5
```

The measured parser time includes YOLOv8 pose decode and bbox NMS.  Application-side preprocessing, camera capture, resize/letterbox, drawing, and video encode are not included in this number.

This number is a board-level measurement, not a universal HAILO-8L maximum. Faster host platforms, different PCIe paths, different HEFs, or different pre/post-processing paths may produce different results.

Actual performance depends on:

- HEF and model size
- Hailo device type
- host SoC / CPU
- PCIe path
- input and output vstream formats
- application-side preprocessing and post-processing
- queue depth and upstream producer behavior

## 🧭 Design notes

`hailort_nim` intentionally keeps responsibilities separated.

```text
Detector:
  synchronous YOLO / NMS-by-class detection

ThreadtoolsVStreamRunner:
  generic vstream write/read overlap

ThreadtoolsDetector:
  threadtools vstream runner + YOLO NMS-by-class parsing

ThreadtoolsDetectorWorker:
  request/reply queue API for YOLO application pipelines

ThreadtoolsInferenceWorker:
  request/reply queue API for raw tensor / custom single-output parser pipelines

MultiOutputInference:
  synchronous multi-output HEF execution and output tensor collection

ThreadtoolsMultiOutputInferenceWorker:
  request/reply queue API for multi-output parser pipelines such as YOLOv8 pose

Application:
  video decode, preprocessing, rendering, encoding, frame dropping policy
```

This keeps the library usable as small, composable parts rather than forcing one large pipeline abstraction.

The threadtools path is the preferred pipeline API. Async integration should be built later as a bridge on top of the threadtools path if it can be done without hurting performance or ownership clarity.

## 🛣️ Future work

Possible future directions:

- Optimized text detection connected-components parser
- OCR recognizer crop / resize helpers
- PoolItem-based output/result paths for codec pipelines
- Async bridge built on top of the threadtools path
- Additional pose-model variants and unified multi-output parser modes
- Segmentation wrappers
- Classification helpers
- License plate detection / recognition pipelines
- GStreamer / libav pipeline examples
- More detailed benchmarking tools

## 📄 License

MIT
