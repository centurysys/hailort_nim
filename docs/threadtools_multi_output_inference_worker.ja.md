# ThreadtoolsMultiOutputInferenceWorker と YOLOv8 pose support

作成日: 2026-06-14

このメモは、複数の output vstream を持つ HEF を `hailort_nim` から扱うための multi-output inference path と、最初の high-level parser として追加した `yolov8s_pose` 対応について説明します。

## 1. 位置づけ

`hailort_nim` の high-level path は、おおまかに以下のように分かれます。

```text
ThreadtoolsDetectorWorker
  single-output YOLO / HAILO_NMS_BY_CLASS detections

ThreadtoolsInferenceWorker
  single-output raw tensor / text detection / custom parser results

ThreadtoolsMultiOutputInferenceWorker
  multi-output HEF
  現時点では YOLOv8 pose -> PoseResult
```

multi-output worker は、既存の `ThreadtoolsDetectorWorker` をすぐ置き換えるものではありません。single-output NMS-by-class YOLO object detection では、従来どおり detector worker が簡単です。multi-output worker は、YOLOv8 pose のように複数 tensor を組み合わせて解釈する必要があるモデル向けです。

## 2. YOLOv8 pose の output layout

検証した `yolov8s_pose` HEF は 9個の output vstream を持ちます。3つの grid scale があり、それぞれに bbox regression、person score、keypoint tensor があります。

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

`64` は `4 sides * 16 DFL bins` です。`51` は `17 COCO keypoints * 3 values` です。

parser は `FLOAT32` user output buffer を前提にしています。worker を開始する前に、`MultiOutputInference` を `outputFormatType = HAILO_FORMAT_TYPE_FLOAT32` で open してください。

## 3. Result 型

pose parser は、generic な `HailoInferenceResult` wrapper の中に `PoseResult` を返します。

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

keypoint の順番は COCO 17-keypoint order です。

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

bbox だけを YOLO 風の normalized `Detection` として扱いたい場合、`PoseDetection.toDetection()` と `poses.toDetections()` が使えます。この互換変換では keypoint 情報は捨てます。

## 4. Parser configuration

`initYolov8PoseParserConfig()` を使います。

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

主なパラメータ:

```text
inputWidth / inputHeight
  model input の座標系。yolov8s_pose では通常 640 x 640

scoreThreshold
  candidate decode / NMS 前に使う person score のしきい値

jointThreshold
  keypoint を描画・利用するときの visibility 目安

iouThreshold
  pose NMS の bbox IoU threshold

candidateLimit
  score sort 後、NMS 前に残す candidate 数の上限

maxPoses
  NMS 後に返す pose detection 数の上限

classId
  pose detection を bbox-only Detection に変換するときの class id
```

## 5. Worker の開始

`MultiOutputInference` として model を open し、FLOAT32 output を要求してから worker を開始します。

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

`startThreadtoolsMultiOutputInferenceWorker()` が成功したあとは、worker が `model` を所有します。以降、`model.inferRaw*()` や `model.close()` を直接呼ばず、worker を close してください。

## 6. Submit / receive

worker は他の threadtools worker と同じ request/reply 型 API です。

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

入力 `seq[byte]` の ownership を worker に渡せる場合は `submit()` を使います。

borrowed な `openArray[byte]` を渡し、元 buffer を呼び出し側に残したい場合は `submitCopy()` を使います。

入力 tensor を `threadtools` の pool で管理している pipeline では、`submitPooled()` / `submitPoolItem()` を使います。

## 7. Queue pump rule

queue が小さい状態で「先に大量 submit してから reply を全部読む」という使い方は避けてください。

caller が request queue を埋め、worker が reply queue を埋めた状態になると、両者が待ち合って deadlock します。

以下のような bounded pump にします。

```text
submit while inFlight < maxInFlight
wait one reply
submit next
wait one reply
...
```

`threadtools_yolov8_pose_probe.nim` はこの方式です。

`recommendedThreadtoolsMultiOutputInferenceWorkerRequestQueueSize(slotCount)` は、single-output worker と同じく `slotCount * 2` 目安です。`initThreadtoolsYolov8PoseWorkerConfig()` は `replyQueueSize = requestQueueSize + 1` を設定します。

## 8. Shutdown と ownership

明示的に stop / join します。

```nim
discard worker.stop()
discard worker.join()
```

または:

```nim
discard worker.close()
```

大きい reply payload を使い終わったら、shutdown 前に clear しておくと安全です。

```nim
reply.clear()
discard worker.close()
```

multi-output inference の output buffer は worker thread 側で確保・再利用し、worker thread 終了直前に同じ thread 側で解放します。これにより、`join()` / `close()` 時に owner thread 側で大きな `seq[seq[byte]]` storage を解放してしまうことを避けています。

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

overlay output を変換:

```sh
ffmpeg -y -i pose_worker_overlay.ppm pose_worker_overlay.png
```

## 10. 検証済みの結果

1人画像:

```text
raw candidates : 11
nms input      : 11
poses          : 1
```

3人画像:

```text
raw candidates : 30
nms input      : 30
poses          : 3
```

TI AM67A + HAILO-8L、pre-resize 済み 640 x 640 RGB input、release build では約 37 fps でした。

```text
avg write      : about 1.2 ms
avg read       : about 22 ms
avg parse      : about 0.8 ms
profile total  : about 26.7 ms
```

camera capture、resize/letterbox、描画、encoding、application-side event logic は含まれていません。

## 11. 現在の制限

- multi-output worker は現時点で `tmopYolov8Pose` のみ実装しています。
- 内部では同期 `MultiOutputInference` を 1 request ずつ処理します。
- parser は YOLOv8 pose head layout、つまり grid ごとの `64 / 1 / 51` channel 構成を前提にしています。
- FLOAT32 user output buffer が必要です。
- letterbox / original image coordinate への復元は application 側の責務です。
- skeleton drawing は example/probe の機能であり、worker API の責務ではありません。
