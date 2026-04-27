# hailort_nim

## Overview

`hailort_nim` is a Nim binding for HailoRT, providing both low-level and high-level APIs for running inference on HAILO-8 / HAILO-8L devices.

- Zero-copy oriented API
- Low-latency inference
- Explicit resource control
- Designed for embedded / edge environments

---

# 🚀 Quick Start

Run object detection with YOLO:

```nim
let detector = Detector.open("yolov11n.hef").get()
let detections = detector.detectNmsByClassAuto(input).get()

echo detections[0].classId
```

Example output:

```text
dog
```

📷 Example image:
![dog](examples/dog.jpg)

---

# ⚠️ Important: DO NOT use open/close in a loop

This is **very important**.

❌ Bad:

```nim
for frame in stream:
  let d = Detector.open("model.hef")
  d.detect(...)
  d.close()
```

This causes:

- SRAM accumulation
- Eventually:
  - HAILO_OUT_OF_PHYSICAL_DEVICES
  - SRAM_FULL

---

# ✅ New Feature: Fast Model Switching (activate/deactivate)

This repository introduces a **correct and efficient way to use multiple models**.

## Concept

```text
openPrepared (once) → activate → infer → deactivate
```

## Example

```nim
let runtime = HailoRuntime.open().get()

let detA = Detector.openPrepared(runtime, "a.hef").get()
let detB = Detector.openPrepared(runtime, "b.hef").get()

while true:
  detA.activate().check()
  detA.detect(...)
  detA.deactivate().check()

  detB.activate().check()
  detB.detect(...)
  detB.deactivate().check()
```

---

# ⏱ Performance

Measured (HAILO-8L + YOLOv11n):

| Operation        | Time |
|-----------------|------|
| prepare         | ~150–400 ms |
| activate        | ~2–3 ms |
| deactivate      | ~1 ms |
| inference       | ~30 ms |

### Key Point

👉 Model switching is **NOT loading**

It is:

```text
context switch only
```

---

# 🧠 Model Capacity

Test result:

- yolov11n.hef (~12MB)
- 12 models prepared simultaneously
- All models can run via activate/deactivate

### Important

- HEF size ≠ runtime memory usage
- Hailo uses streaming / partitioned execution
- Actual memory footprint is much smaller

---

# 🧩 API Summary

## Simple (single model)

```nim
Detector.open()
Detector.detect()
```

## Advanced (multi-model)

```nim
Detector.openPrepared()
detector.activate()
detector.deactivate()
```

---

# 🎯 Design Philosophy

Hailo is designed for:

```text
Load once → reuse → switch context
```

NOT:

```text
Load → run → unload
```

---

# 📦 Future Work

- Vision pipeline (GStreamer integration)
- Multi-model scheduler
- Pose / segmentation support

---

# Summary

- Keep Quick Start simple
- NEVER use open/close in loops
- Use activate/deactivate for multi-model

This enables:

- Stable execution
- Low latency switching
- Efficient multi-model inference
