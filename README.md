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
- Optional async-style vstream runner for higher-throughput pipelines
- `AsyncDetector` wrapper for async YOLO / NMS-by-class detection
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

## ⚡ Async vstream support

`hailort_nim` includes optional async-style vstream support for applications that need higher throughput.

The goal is to overlap:

- input vstream writes
- blocking output vstream reads
- application-side post-processing

HailoRT vstream `read()` is blocking. `AsyncVStreamRunner` keeps the input write on the caller thread, but moves the blocking output read path to an internal read thread.

This improves pipeline structure without requiring raw stream async APIs.

### 🧱 Build requirements

Async vstream support uses Nim threads internally.

Build examples or applications using it with:

```bash
nim c --threads:on -d:hailortAsyncVstream -d:release examples/async_vstream_runner_split_task_probe.nim
```

The normal synchronous API can remain usable without `--threads:on` when async vstream exports are guarded behind `-d:hailortAsyncVstream`.

A typical top-level export guard looks like this:

```nim
when defined(hailortAsyncVstream):
  import ./hailort_nim/highlevel/async_vstream_runner
  import ./hailort_nim/highlevel/async_detector
  export async_vstream_runner
  export async_detector
```

### 🧵 AsyncVStreamRunner

`AsyncVStreamRunner` is model-agnostic. It only handles vstream I/O overlap and output slot management.

```nim
let det = Detector.open("yolov11s.hef").get()
defer:
  discard det.close()

let runner = det.openAsyncVStreamRunner(slotCount = 2).get()
defer:
  discard runner.close()
```

The recommended split-task API is:

```nim
let ready = await runner.waitWritable()
if ready.isErr:
  quit($ready.error)

let readFuture = runner.writeAsync(input).get()

# readFuture can be passed to another async task.

let result = (await readFuture).get()

try:
  # Parse or consume result.outputPtr / result.outputSize here.
  discard
finally:
  discard runner.releaseResult(result)
```

Why the API is split:

- `waitWritable()` is async and may await an output slot.
- `writeAsync()` is intentionally not an async proc.
- This avoids capturing `openArray[byte]` across an `await` boundary.
- The input buffer is consumed synchronously by `inputVstream.write()`.

### 📦 AsyncVStreamResult

`AsyncVStreamResult` contains:

```nim
type
  AsyncVStreamResult* = object
    slotIndex*: int
    outputPtr*: pointer
    outputSize*: int
    writeUs*: int64
    readUs*: int64
```

The output buffer is owned by `AsyncVStreamRunner`. The caller may read `outputPtr` until `releaseResult()` is called.

Always release the result:

```nim
discard runner.releaseResult(result)
```

If results are not released, output slots are not returned to the runner.

### 🔎 AsyncDetector

`AsyncDetector` is a YOLO / NMS-by-class wrapper built on top of `AsyncVStreamRunner`.

```text
AsyncVStreamRunner:
  model-agnostic vstream I/O overlap

AsyncDetector:
  AsyncVStreamRunner + YOLO NMS-by-class parsing
```

This separation keeps the async vstream runner reusable for other model families such as pose estimation, segmentation, classification, OCR, or license plate recognition.

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

### ⚡ Async vstream runner probe

```bash
nim c --threads:on -d:hailortAsyncVstream -d:release examples/async_vstream_runner_probe.nim
./examples/async_vstream_runner_probe yolov11s.hef dog.raw 100 2
```

### 🔎 Async detector probe

```bash
nim c --threads:on -d:hailortAsyncVstream -d:release examples/async_detector_probe.nim
./examples/async_detector_probe yolov11s.hef dog.raw 100 2 0.25
```

### 🧩 Split async task probe

This example demonstrates an application-like structure where the write task and read/result task are separated.

```bash
nim c --threads:on -d:hailortAsyncVstream -d:release examples/async_vstream_runner_split_task_probe.nim
./examples/async_vstream_runner_split_task_probe yolov11s.hef dog.raw 100 2
```

## 📈 Throughput notes

In local HAILO-8L testing with YOLOv11 models, two in-flight slots were enough to significantly improve throughput compared with a strictly synchronous write/read loop.

A practical starting point is:

```nim
let runner = det.openAsyncVStreamRunner(slotCount = 2).get()
```

Increasing the slot count beyond two did not improve throughput in those tests.

Actual performance depends on:

- HEF and model size
- Hailo device type
- host CPU
- PCIe path
- input and output vstream formats
- application-side preprocessing and post-processing

## 🧭 Design notes

`hailort_nim` intentionally keeps responsibilities separated.

```text
Detector:
  synchronous YOLO / NMS-by-class detection

AsyncVStreamRunner:
  generic vstream write/read overlap

AsyncDetector:
  async YOLO / NMS-by-class detection

Application:
  video decode, preprocessing, rendering, encoding, frame dropping policy
```

This keeps the library usable as small, composable parts rather than forcing one large pipeline abstraction.

## 🛣️ Future work

Possible future directions:

- Higher-level async object detection helpers
- Pose estimation wrappers
- Segmentation wrappers
- Classification helpers
- License plate detection / recognition pipelines
- GStreamer integration examples
- Eventfd-based completion notification to replace polling
- More detailed benchmarking tools

## 📄 License

MIT
