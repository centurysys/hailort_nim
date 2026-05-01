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
- スループット向上用の async-style vstream runner
- YOLO / NMS-by-class 用の `AsyncDetector`
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

## ⚡ Async vstream support

`hailort_nim` には、スループット向上用の async-style vstream support があります。

目的は以下を重ねることです。

- input vstream write
- blocking な output vstream read
- アプリ側の後処理

HailoRT の vstream `read()` は blocking です。`AsyncVStreamRunner` は、input write は caller thread で同期実行し、長く待つ output read を内部 read thread に逃がします。

これにより、raw stream async API に踏み込まずに、既存 vstream API の上でパイプライン化できます。

### 🧱 ビルド条件

Async vstream support は Nim の thread を使います。

使う場合は `--threads:on` が必要です。

```bash
nim c --threads:on -d:hailortAsyncVstream -d:release examples/async_vstream_runner_split_task_probe.nim
```

通常の同期 API は、async vstream の export を `-d:hailortAsyncVstream` で guard しておけば、`--threads:on` なしでも使える構成にできます。

top-level export の例:

```nim
when defined(hailortAsyncVstream):
  import ./hailort_nim/highlevel/async_vstream_runner
  import ./hailort_nim/highlevel/async_detector
  export async_vstream_runner
  export async_detector
```

### 🧵 AsyncVStreamRunner

`AsyncVStreamRunner` は model-agnostic な部品です。vstream I/O の重ね合わせと output slot 管理だけを担当します。

```nim
let det = Detector.open("yolov11s.hef").get()
defer:
  discard det.close()

let runner = det.openAsyncVStreamRunner(slotCount = 2).get()
defer:
  discard runner.close()
```

推奨する split-task API は以下です。

```nim
let ready = await runner.waitWritable()
if ready.isErr:
  quit($ready.error)

let readFuture = runner.writeAsync(input).get()

# readFuture は別の async task に渡せます。

let result = (await readFuture).get()

try:
  # result.outputPtr / result.outputSize を parse する
  discard
finally:
  discard runner.releaseResult(result)
```

API を分けている理由:

- `waitWritable()` は async で、output slot の空きを await する。
- `writeAsync()` は意図的に async proc ではない。
- これにより、`openArray[byte]` を `await` 境界をまたいで capture しない。
- input buffer は `inputVstream.write()` の同期呼び出し中に消費される。

### 📦 AsyncVStreamResult

`AsyncVStreamResult` には以下が入ります。

```nim
type
  AsyncVStreamResult* = object
    slotIndex*: int
    outputPtr*: pointer
    outputSize*: int
    writeUs*: int64
    readUs*: int64
```

output buffer は `AsyncVStreamRunner` が所有します。`releaseResult()` するまでは `outputPtr` を読めます。

使い終わったら必ず release してください。

```nim
discard runner.releaseResult(result)
```

release しないと output slot が戻らず、後続の推論が詰まります。

### 🔎 AsyncDetector

`AsyncDetector` は、`AsyncVStreamRunner` の上にある YOLO / NMS-by-class 用 wrapper です。

```text
AsyncVStreamRunner:
  model-agnostic な vstream I/O overlap

AsyncDetector:
  AsyncVStreamRunner + YOLO NMS-by-class parse
```

この分離により、将来の pose estimation、segmentation、classification、OCR、ナンバープレート認識などにも `AsyncVStreamRunner` を流用できます。

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

write task と read/result task を分けた、アプリに近い構成の example です。

```bash
nim c --threads:on -d:hailortAsyncVstream -d:release examples/async_vstream_runner_split_task_probe.nim
./examples/async_vstream_runner_split_task_probe yolov11s.hef dog.raw 100 2
```

## 📈 スループットに関するメモ

HAILO-8L と YOLOv11 系 HEF を使った手元の計測では、in-flight slot を 2 個にすることで、完全同期の write/read loop より大きくスループットが改善しました。

まずは以下を推奨値にしています。

```nim
let runner = det.openAsyncVStreamRunner(slotCount = 2).get()
```

手元の計測では、slot を 2 より増やしても大きな改善はありませんでした。

実際の性能は以下に依存します。

- HEF とモデルサイズ
- Hailo デバイス種別
- host CPU
- PCIe 経路
- input / output vstream format
- アプリ側の前処理・後処理

## 🧭 設計方針

`hailort_nim` は、責務を分ける方針です。

```text
Detector:
  同期版 YOLO / NMS-by-class detection

AsyncVStreamRunner:
  汎用 vstream write/read overlap

AsyncDetector:
  async YOLO / NMS-by-class detection

Application:
  video decode, preprocessing, rendering, encoding, frame drop policy
```

巨大な万能 pipeline にするのではなく、小さく組み合わせやすい部品を提供する方針です。

## 🛣️ 今後の候補

- より高レベルな async object detection helper
- pose estimation wrapper
- segmentation wrapper
- classification helper
- ナンバープレート検出・認識 pipeline
- GStreamer 連携 example
- polling ではなく eventfd を使った completion notification
- 詳細 benchmark tools

## 📄 License

MIT
