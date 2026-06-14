# ThreadtoolsMultiOutputInferenceWorker and YOLOv8 pose support

Date: 2026-06-14

This note describes the multi-output inference path added for HEFs that expose more than one output vstream, with `yolov8s_pose` as the first supported high-level parser.

## 1. Positioning

`hailort_nim` now has separate high-level paths for the common output shapes:

```text
ThreadtoolsDetectorWorker
  single-output YOLO / HAILO_NMS_BY_CLASS detections

ThreadtoolsInferenceWorker
  single-output raw tensor / text detection / custom parser results

ThreadtoolsMultiOutputInferenceWorker
  multi-output HEFs
  currently: YOLOv8 pose -> PoseResult
```

The multi-output worker is not intended to replace `ThreadtoolsDetectorWorker` immediately.  The detector worker remains the convenience API for existing single-output NMS-by-class YOLO object detection models.  The multi-output worker exists for models whose output needs multiple tensors to be interpreted together, such as YOLOv8 pose.

## 2. YOLOv8 pose output layout

The tested `yolov8s_pose` HEF exposes nine output vstreams: three grid scales, each with bbox regression, person score, and keypoint tensors.

```text
80 x 80 x 64   bbox regression, DFL logits
80 x 80 x 1    person score
80 x 80 x 51   keypoints, 17 * (x, y, score/logit)

40 x 40 x 64   bbox regression, DFL logits
40 x 40 x 1    person score
40 x 40 x 51   keypoints

20 x 20 x 64   bbox regression, DFL logits
20 x 20 x 1    person score
20 x 20 x 51   keypoints
```

`64` means `4 sides * 16 DFL bins`.  `51` means `17 COCO keypoints * 3 values`.

The parser expects `FLOAT32` user output buffers.  Open `MultiOutputInference` with `outputFormatType = HAILO_FORMAT_TYPE_FLOAT32` before starting the worker.

## 3. Result types

The pose parser returns `PoseResult` through the generic `HailoInferenceResult` wrapper.

```text
HailoInferenceResult
  kind = hrkPose
  pose = PoseResult

PoseResult
  poses: seq[PoseDetection]

PoseDetection
  score
  classId
  bbox
  center
  sourceScale
  cellX / cellY
  keypoints[17]

PoseKeypoint
  x
  y
  score
```

Keypoints use the COCO 17-keypoint order:

```text
0  nose
1  left eye
2  right eye
3  left ear
4  right ear
5  left shoulder
6  right shoulder
7  left elbow
8  right elbow
9  left wrist
10 right wrist
11 left hip
12 right hip
13 left knee
14 right knee
15 left ankle
16 right ankle
```

`PoseDetection.toDetection()` and `poses.toDetections()` are available when an application needs a YOLO-like normalized `Detection` view.  That compatibility view drops keypoint data.

## 4. Parser configuration

Use `initYolov8PoseParserConfig()`.

```nim
let poseConfig = initYolov8PoseParserConfig(
  inputWidth = 640,
  inputHeight = 640,
  scoreThreshold = 0.25'f32,
  jointThreshold = 0.5'f32,
  iouThreshold = 0.45'f32,
  candidateLimit = 100,
  maxPoses = 20,
  classId = 0
)
```

Main parameters:

```text
inputWidth / inputHeight
  model input coordinate space, usually 640 x 640 for yolov8s_pose

scoreThreshold
  minimum person score used before candidate decode/NMS

jointThreshold
  recommended visibility threshold for drawing or consuming keypoints

iouThreshold
  bbox IoU threshold for pose NMS

candidateLimit
  maximum number of pre-NMS candidates kept after score sorting

maxPoses
  maximum number of post-NMS pose detections returned

classId
  class id used when converting pose detections to bbox-only Detection records
```

## 5. Starting the worker

Open the model as `MultiOutputInference`, request `FLOAT32` outputs, then start the worker.

```nim
import hailort_nim

let model = MultiOutputInference.open(
  "yolov8s_pose.hef",
  profiling = true,
  outputFormatType = HAILO_FORMAT_TYPE_FLOAT32
).get()

let poseConfig = initYolov8PoseParserConfig(
  scoreThreshold = 0.25'f32,
  jointThreshold = 0.5'f32,
  iouThreshold = 0.45'f32,
  candidateLimit = 100,
  maxPoses = 20
)

let workerConfig = initThreadtoolsYolov8PoseWorkerConfig(
  slotCount = 1,
  poseConfig = poseConfig
)

let worker = startThreadtoolsMultiOutputInferenceWorker(model, workerConfig).get()
```

After `startThreadtoolsMultiOutputInferenceWorker()` succeeds, the worker owns `model`.  Do not call `model.inferRaw*()` or `model.close()` directly.  Close the worker instead.

## 6. Submit and receive

The worker has the same broad request/reply style as the other threadtools workers.

```nim
discard worker.submitCopy(
  input = input640x640Rgb,
  requestId = frameId,
  userData = timestampOrFrameKey
)

var reply: ThreadtoolsMultiOutputInferenceWorkerReply
let rr = worker.waitReply(reply)
if rr.isErr:
  quit($rr.error)

case reply.kind
of tmowrkResult:
  let infp = addr reply.result.inference
  if infp[].kind == hrkPose:
    for pose in infp[].pose.poses:
      echo pose.score
of tmowrkError:
  quit(reply.error.msg)

reply.clear()
```

Use `submit()` when ownership of a `seq[byte]` can be moved to the worker.

Use `submitCopy()` when the caller has a borrowed `openArray[byte]` and wants to keep the original buffer.

Use `submitPooled()` / `submitPoolItem()` when input tensors are managed by a `threadtools` pool.

## 7. Queue pump rule

Do not submit many requests first and only then receive all replies, unless the queues are sized to hold the whole burst.

A small worker queue can deadlock if the caller fills the request queue while the worker fills the reply queue and both sides wait.

Use a bounded pump:

```text
submit while inFlight < maxInFlight
wait one reply
submit next
wait one reply
...
```

The example `threadtools_yolov8_pose_probe.nim` uses this pattern.

`recommendedThreadtoolsMultiOutputInferenceWorkerRequestQueueSize(slotCount)` currently follows the same `slotCount * 2` convention as the single-output worker.  `replyQueueSize` is set to `requestQueueSize + 1` by `initThreadtoolsYolov8PoseWorkerConfig()`.

## 8. Shutdown and ownership

Use explicit shutdown:

```nim
discard worker.stop()
discard worker.join()
```

or:

```nim
discard worker.close()
```

Clear any large reply payload after the application has consumed it and before shutdown when convenient:

```nim
reply.clear()
discard worker.close()
```

The worker allocates and reuses multi-output buffers on the worker thread.  Those buffers are also released on the worker thread before exit.  This avoids freeing large `seq[seq[byte]]` storage from the owner thread during `join()` / `close()`.

## 9. Examples

### Synchronous parser probe

```sh
nim c -d:release examples/multi_output_yolov8_pose_probe.nim

./multi_output_yolov8_pose_probe \
  yolov8s_pose.hef \
  pose_test_640x640_rgb.raw \
  0.25 100 \
  pose_overlay.ppm \
  0.5 0.45 20
```

### Threadtools worker probe

```sh
nim c -d:hailortThreadtools -d:release examples/threadtools_yolov8_pose_probe.nim

./threadtools_yolov8_pose_probe \
  yolov8s_pose.hef \
  pose_test_640x640_rgb.raw \
  10 0.25 100 \
  pose_worker_overlay.ppm \
  0.5 0.45 20
```

Convert overlay output:

```sh
ffmpeg -y -i pose_worker_overlay.ppm pose_worker_overlay.png
```

## 10. Observed validation results

Single-person test image:

```text
raw candidates : 11
nms input      : 11
poses          : 1
```

Three-person test image:

```text
raw candidates : 30
nms input      : 30
poses          : 3
```

Release-build throughput on TI AM67A + HAILO-8L with pre-resized 640 x 640 RGB input was about 37 fps:

```text
avg write      : about 1.2 ms
avg read       : about 22 ms
avg parse      : about 0.8 ms
profile total  : about 26.7 ms
```

This does not include camera capture, resize/letterbox, drawing, encoding, or application-side event logic.

## 11. Current limitations

- The multi-output worker currently implements only `tmopYolov8Pose`.
- It executes one synchronous `MultiOutputInference` request at a time.
- The parser assumes YOLOv8 pose head layout: `64 / 1 / 51` channels grouped by grid size.
- It expects FLOAT32 user output buffers.
- Letterbox/original-image coordinate restoration is still the application's responsibility.
- Skeleton drawing is an example/probe feature, not part of the worker API.
