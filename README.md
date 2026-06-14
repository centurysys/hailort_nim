# hailort_nim

`hailort_nim` is a Nim binding and high-level helper library for HailoRT.

It provides low-level access to the HailoRT C API and higher-level APIs for running inference on HAILO-8 / HAILO-8L devices from Nim applications.

The current high-level API is focused on YOLO-style object detection models that output `HAILO_FORMAT_ORDER_HAILO_NMS_BY_CLASS`.

## ✨ Features

- Low-level Nim bindings for HailoRT
- High-level `Detector` API for YOLO / NMS-by-class models
- Explicit open / activate / deactivate / close lifecycle control
- Multi-HEF preparation and fast model switching
- Optional inference profiling for the high-level `Detector`
- Optional `threadtools`-based detector runner for streaming / pipeline-style applications
- Worker-style submit / receive API with request correlation metadata
- Pooled input submission using `threadtools` pool items for pipeline-style ownership transfer
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

The threadtools path provides two levels:

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
  suitable for application / codec pipeline integration
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
  request/reply queue API for application pipelines

Application:
  video decode, preprocessing, rendering, encoding, frame dropping policy
```

This keeps the library usable as small, composable parts rather than forcing one large pipeline abstraction.

The threadtools path is the preferred pipeline API. Async integration should be built later as a bridge on top of the threadtools path if it can be done without hurting performance or ownership clarity.

## 🛣️ Future work

Possible future directions:

- PoolItem-based output/result paths for codec pipelines
- Async bridge built on top of the threadtools path
- Pose estimation wrappers
- Segmentation wrappers
- Classification helpers
- License plate detection / recognition pipelines
- GStreamer / libav pipeline examples
- More detailed benchmarking tools

## 📄 License

MIT
