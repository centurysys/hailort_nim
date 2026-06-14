# hailort_nim

`hailort_nim` は、HailoRT を Nim から使うための binding / high-level helper ライブラリです。

HAILO-8 / HAILO-8L デバイスで推論を実行するための低レベル API と、YOLO 系モデルを扱いやすくする高レベル API を提供します。

現在の high-level API は、主に `HAILO_FORMAT_ORDER_HAILO_NMS_BY_CLASS` を出力する YOLO 系 object detection モデルを対象にしています。

## ✨ 特長

- HailoRT C API の Nim binding
- YOLO / NMS-by-class モデル向けの high-level `Detector` API
- open / activate / deactivate / close の明示的なライフサイクル管理
- 複数 HEF の事前準備と高速なモデル切り替え
- `Detector` の推論経路 profiling
- streaming / pipeline 型アプリ向けの optional `threadtools` 連携
- request correlation metadata 付きの worker 型 submit / receive API
- pipeline 型の所有権移動に向いた `threadtools` pool item 入力
- 組み込み Linux / edge device 向けの設計

## ⚠️ 重要: open / close をフレームループ内で繰り返さない

HEF をフレームごとに open / close しないでください。

悪い例:

```nim
for frame in frames:
  let det = Detector.open("yolov11n.hef").get()
  let detections = det.detectNmsByClassAuto(frame).get()
  discard det.close()
```

これは非効率で、HailoRT 側のリソース圧迫につながる可能性があります。

基本は、open once / reuse です。

```nim
let det = Detector.open("yolov11n.hef").get()
defer:
  discard det.close()

for frame in frames:
  let detections = det.detectNmsByClassAuto(frame).get()
```

複数モデルを使う場合は、事前に準備して `activate()` / `deactivate()` で切り替えます。

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

入力バッファは、HEF が要求する input vstream format / frame size と一致している必要があります。

YOLO HEF では 640 x 640 RGB byte buffer のことが多いですが、正確な形式は HEF の作り方によります。metadata helper や `hailortcli parse-hef` で確認してください。

## 🔍 Detector API

同期版の `Detector` API がもっとも単純な入口です。

```nim
let detector = Detector.open("yolov11n.hef").get()
let detections = detector.detectNmsByClassAuto(input).get()
```

高頻度ループでは、可能な範囲で caller 側の buffer / seq を再利用する API を使う方が有利です。

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

## 🔁 複数モデルの扱い

HEF の open / configure は重い処理です。複数 HEF を切り替えるアプリでは、prepared model flow を使います。

概念:

```text
runtime を一度 open
model を一度 prepare
model A を activate
infer
model A を deactivate
model B を activate
infer
model B を deactivate
```

例:

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

これにより、HEF の open / close を繰り返さず、runtime 上の軽い切り替えとして扱えます。

## ⏱️ Detector profiling

`Detector` には、推論経路の簡易 profiling 機能があります。

open 時に有効化できます。

```nim
let detector = Detector.open("yolov11n.hef", profiling = true).get()
```

または後から有効化できます。

```nim
detector.enableProfiling()
```

推論後に summary を出せます。

```nim
echo detector.profileSummary()
detector.resetProfile()
```

計測対象は以下です。

- 入力 validation
- input vstream write
- output vstream read
- NMS output parse
- detection sort

host 側処理、HailoRT 転送、デバイス実行待ちのどこで時間を使っているかを切り分けるのに使えます。

## 🧵 Threadtools detector support

`hailort_nim` には、継続的に frame / tensor を HAILO へ流す worker 型 pipeline 向けに、optional の `threadtools` 連携があります。

目的は、blocking な HailoRT vstream read を `asyncdispatch` 中心の API で無理に包まず、HAILO を埋め続けられる構成を作ることです。

threadtools 経路は、以下の 3 段に分かれています。

```text
ThreadtoolsVStreamRunner:
  model-agnostic な vstream write/read overlap
  caller が input buffer を submit
  内部 read worker が output vstream result を待つ

ThreadtoolsDetector:
  ThreadtoolsVStreamRunner + YOLO NMS-by-class parse
  caller が input buffer を submit し、parse 済み detections を受け取る

ThreadtoolsDetectorWorker:
  request queue + reply queue + detector worker thread
  application / codec pipeline から使うための API
```

### ビルド条件

threadtools 経路は `-d:hailortThreadtools` で有効化します。

```bash
nim c -d:hailortThreadtools -d:release examples/threadtools_detector_worker_probe.nim
```

最近の Nim 2.x 環境では thread がデフォルト有効になっていることがあります。設定によって無効な場合は `--threads:on` を追加してください。

threadtools 経路を使うには、`threadtools` と `move_results` パッケージが Nimble または Nim の module search path から見えている必要があります。

### ThreadtoolsDetector

`ThreadtoolsDetector` は、submit / receive の順序を caller 側で制御しつつ、blocking な output read を内部 vstream read worker に逃がしたい場合に使います。

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

この経路では parse 後に output slot を内部で release するため、caller が vstream output pointer の寿命を直接管理する必要はありません。

### ThreadtoolsDetectorWorker

`ThreadtoolsDetectorWorker` は、pipeline 型アプリ向けの推奨 API です。

detector worker thread を持ち、queue 型 interface を提供します。

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

pipeline では、入力 buffer の所有権を worker に渡せるなら、`seq[byte]` を move して渡す `submit()` を優先します。

caller が `openArray[byte]` を持っている場合や、元の buffer を保持したい場合の convenience API として `submitCopy()` を使えます。

入力 tensor が `threadtools` pool で管理されている streaming pipeline では、`submitPooled()` / `submitPoolItem()` を使います。

```nim
let pool = newPool[seq[byte]](requestQueueSize).get()

# input buffer は別の場所で pool に追加しておく
var item = pool.acquire()

discard worker.submitPooled(
  move item,
  requestId = frameId,
  appScoreThreshold = 0.25'f32,
  userData = cameraFrameKey
)
```

worker は HAILO input vstream write を同期的に実行し、その後 request が worker 経路を抜けたところで pooled input item が元の pool へ自動返却されます。codec / frame pipeline では、この経路が入力 buffer の所有権移動 API として本命です。

### Request correlation

Worker request / reply には、対応付け用の field があります。

```text
requestId:
  連番またはアプリ定義の request identifier

userData:
  アプリ側 metadata 用の opaque uint64
```

これにより、結果を camera / frame / event / timestamp などと対応付けられます。受信順だけに依存する必要はありません。

エラー応答にも同じ metadata が残るため、失敗した request の追跡にも使えます。

### Queue depth

`slotCount = 2` の場合、request queue size は最低 4 を推奨します。

queue depth が slot count と同じだと、reply の合間に worker pipeline が空き、HAILO vstream 経路を埋め続けられないことがあります。

以下を使うのが基本です。

```nim
let qsize = recommendedThreadtoolsDetectorWorkerRequestQueueSize(slotCount)
```

TI AM67A（Cortex-A53 1.4 GHz x 4 コア） + HAILO-8L + YOLOv11s の手元計測では、request queue を `slotCount * 2` より増やしても throughput は改善しませんでした。ただし、アプリ側で意図的に入力を多めに buffer したい場合には、より大きな queue depth を指定できます。

### Shutdown

worker は明示的な graceful shutdown を持ちます。

```nim
discard worker.stop()
discard worker.join()
```

`close()` は stop + join の convenience wrapper です。

`stop()` は graceful です。投入済み request は drain されてから worker が終了します。stop 開始後の新規 submit は拒否されます。

## 🧪 Examples

### ▶️ 同期推論

```bash
nim c -d:release examples/infer_high.nim
./examples/infer_high yolov11n.hef dog_640x640x3.raw
```

### ⏱️ profiling example

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

この probe は、入力 tensor を `threadtools` pool に事前投入し、pool item を worker へ submit します。borrowed input array を毎回 copy する経路より、実際の codec pipeline で想定している所有権モデルに近い確認用です。

## 📈 スループットに関するメモ

TI AM67A（Cortex-A53 1.4 GHz x 4 コア） + HAILO-8L + YOLOv11s HEF の計測では、通常の worker 経路と pooled-input worker 経路のどちらも、in-flight slot 2 個により約 39.5 fps に到達しています。

```text
loops      : 100
slots      : 2
queue      : 4
fps        : 39.5
avg write  : 約 3.1 ms
avg read   : 約 25.2 ms
avg parse  : 約 0.01 ms
```

実用上の開始点は以下です。

```nim
let slotCount = 2
let requestQueueSize = recommendedThreadtoolsDetectorWorkerRequestQueueSize(slotCount)
```

この数値はボード込みの実測値であり、HAILO-8L 単体の一般的な上限値ではありません。より高速な host platform、PCIe 経路、HEF、前処理・後処理の違いにより結果は変わります。

実際の性能は以下に依存します。

- HEF とモデルサイズ
- Hailo デバイス種別
- host SoC / CPU
- PCIe 経路
- input / output vstream format
- アプリ側の前処理・後処理
- queue depth と upstream producer の挙動

## 🧭 設計方針

`hailort_nim` は、責務を分ける方針です。

```text
Detector:
  同期版 YOLO / NMS-by-class detection

ThreadtoolsVStreamRunner:
  汎用 vstream write/read overlap

ThreadtoolsDetector:
  threadtools vstream runner + YOLO NMS-by-class parse

ThreadtoolsDetectorWorker:
  application pipeline 向け request/reply queue API

Application:
  video decode, preprocessing, rendering, encoding, frame drop policy
```

巨大な万能 pipeline にするのではなく、小さく組み合わせやすい部品を提供する方針です。

pipeline 用 API としては threadtools 経路を優先します。async 連携は、後で threadtools 経路の上に bridge として載せ、性能と所有権管理に問題がない形にできた段階で戻す方針です。

## 🛣️ 今後の候補

- codec pipeline 向けの PoolItem ベース output/result path
- threadtools 経路の上に載せる async bridge
- pose estimation wrapper
- segmentation wrapper
- classification helper
- ナンバープレート検出・認識 pipeline
- GStreamer / libav pipeline example
- 詳細 benchmark tools

## 📄 License

MIT
