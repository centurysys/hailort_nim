# ThreadtoolsInferenceWorker と raw/custom output parser

作成日: 2026-06-14

このメモは、YOLO/NMS 以外の HEF、特に独自モデルや text detection のように「出力 vstream が raw tensor / byte buffer として返る」モデルを `hailort_nim` から扱うための API 整理です。

## 1. 位置づけ

既存の `ThreadtoolsDetectorWorker` は YOLO / NMS-by-class 向けです。

一方、`ThreadtoolsInferenceWorker` は、モデル固有の postprocess をあとから選べる generic worker です。これは single-output HEF 向けです。YOLOv8 pose のように複数 output vstream を持つ HEF では `ThreadtoolsMultiOutputInferenceWorker` を使います。

```text
ThreadtoolsVStreamRunner
  HAILO input write / output read overlap

ThreadtoolsDetectorWorker
  YOLO / HAILO_NMS_BY_CLASS 専用 worker

ThreadtoolsInferenceWorker
  raw tensor / text detection / custom single-output parser 向け generic worker

ThreadtoolsMultiOutputInferenceWorker
  YOLOv8 pose のような multi-output parser 向け generic worker
```

single-output YOLO の通常利用では、既存の `ThreadtoolsDetectorWorker` を使うのが簡単です。独自 single-output model、分類、OCR/text detection のようなモデルでは、まず `ThreadtoolsInferenceWorker` + raw tensor parser で出力を確認してから、モデル固有 parser を足すのが安全です。multi-output model では、まず `MultiOutputInference` で出力を確認し、parser ができた段階で `ThreadtoolsMultiOutputInferenceWorker` を使います。YOLOv8 pose path については `threadtools_multi_output_inference_worker.ja.md` を参照してください。

## 2. 基本ルール

`ThreadtoolsInferenceWorker` は request/reply queue 型 API です。

`waitReply(reply: var ThreadtoolsInferenceWorkerReply): HE[void]` は、戻り値が OK のときだけ `reply` を触る前提です。

```nim
var reply: ThreadtoolsInferenceWorkerReply
let rr = worker.waitReply(reply)
if rr.isErr:
  quit($rr.error)

# rr が OK のときだけ reply を読む
case reply.kind
of tiwrResult:
  echo reply.result.requestId
of tiwrError:
  echo reply.error.message
```

大きい object の copy を避けるため、`HE[ThreadtoolsInferenceWorkerReply]` として返さず、caller が用意した `var reply` に書き込みます。

## 3. metadata は reply に載せない

thread をまたぐ reply には、必要最小限の payload だけを載せます。

```text
reply に載せるもの:
  requestId
  userData
  timings
  parser result payload

reply に載せないもの:
  output vstream name
  network name
  static VStreamMetadata の string fields
```

静的 metadata は worker owner 側から取得します。

```nim
let om = worker.outputMetadata()
echo om.name
```

これは thread queue 越しに運ぶ object を小さくし、ownership / destructor / move hook の事故を避けるための設計です。

## 4. Raw tensor parser

独自モデルの最初の確認には `hopRawTensor` を使います。

```nim
let parserConfig = initRawTensorParserConfig(maxRawBytes = 0)

let worker = openThreadtoolsInferenceWorker(
  hefPath = "custom_model.hef",
  parserConfig = parserConfig,
  slotCount = 2,
  requestQueueSize = 4
).get()
```

`maxRawBytes = 0` は出力全体を取得します。出力が大きい場合、確認用に先頭だけ取りたいときは `maxRawBytes` を指定します。

Raw tensor result は owned payload として返ります。

```nim
let raw = reply.result.inference.raw

echo raw.bytes.len
for i in 0 ..< min(raw.bytes.len, 64):
  echo raw.bytes.byteAt(i)
```

通常の `seq[byte]` が必要な場合は `copyToSeq()` でコピーできます。

```nim
let s = raw.bytes.copyToSeq()
```

## 5. raw output の調査手順

独自 HEF を受け取ったら、まず以下を確認します。

1. input metadata
2. output metadata
3. output size
4. output type
5. output shape
6. raw preview / min / max / histogram

`examples/threadtools_inference_worker_raw_probe.nim` を使うと、raw tensor をそのまま確認できます。

例:

```sh
nim c -d:hailortThreadtools -d:release examples/threadtools_inference_worker_raw_probe.nim

./threadtools_inference_worker_raw_probe \
  custom_model.hef \
  input_960x544_rgb.raw \
  10 2 4 0 64 \
  custom_output.raw
```

最後の `custom_output.raw` を指定すると、最後の reply の raw output をファイルへ保存します。

## 6. raw output を画像化する例

出力が `UINT8` の 1ch score map で、shape が `544 x 960 x 1` の場合:

```sh
ffmpeg -y \
  -f rawvideo \
  -pixel_format gray \
  -video_size 960x544 \
  -i custom_output.raw \
  custom_output.png
```

`video_size` は `width x height` なので、HAILO metadata が `HxWxC = 544x960x1` なら `960x544` を指定します。

出力値の分布確認:

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

`paddle_ocr_v5_mobile_detection` のような text detection モデルでは、出力が `544 x 960 x 1` の UINT8 score map として返ります。

`hopTextDetectionDb` は、この score map を CPU 側で処理して `TextRegionResult` へ変換します。

処理内容は、現時点では簡易版です。

```text
UINT8 score map
  threshold
  connected components
  min area / min width / min height filter
  bbox padding
  sort
  TextRegionResult
```

完全な DBPostProcess ではありませんが、text line bbox を得る最初の実装としては有効です。

## 8. TextDetectionParserConfig

主なパラメータ:

```text
threshold:
  score map の二値化しきい値

minArea:
  小さい region を除外する面積しきい値

minWidth / minHeight:
  細すぎる region を除外するサイズしきい値

padX / padY:
  bbox を crop しやすいように広げる pixel 数

maxRegions:
  返す region 数の上限。0 は無制限

sortBy:
  top-left / score desc / area desc
```

テスト画像の例では、以下が扱いやすい初期値でした。

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

`examples/threadtools_text_detection_probe.nim` は、text detection parser 経由で HEF を実行し、bbox 一覧と overlay PPM を出力します。

例:

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

overlay を PNG に変換:

```sh
ffmpeg -y -i overlay.ppm overlay.png
```

## 10. YOLO 風 result として扱う

`TextRegion` は、必要に応じて `Detection` に変換できます。

```nim
let det = region.toDetection(imageWidth = 960, imageHeight = 544, classId = 0)
let detections = result.regions.toDetections(imageWidth = 960, imageHeight = 544, classId = 0)
```

このとき、`classId = 0` は `text` class として扱う想定です。

ただし、text detection の bbox は看板単位ではなく、文字行単位で出ることが多いです。

```text
OPEN 24 HOURS:
  OPEN
  24 HOURS

Wi-Fi Available:
  Wi-Fi
  Available
```

この挙動は text detector として自然です。後段の OCR recognizer へ渡す単位としては、文字行 bbox のほうが扱いやすいことが多いです。

## 11. 独自モデル向け parser を追加する流れ

独自モデルの出力仕様が分かっている場合は、以下の順で進めます。

1. `hopRawTensor` で raw output を保存
2. metadata / shape / type / value range を確認
3. output の意味を仕様書や Python reference と照合
4. `inference_result.nim` に result 型を追加するか既存型に載せる
5. parser module を追加する
6. `inference_parser.nim` の `parseOutputInto()` に parser kind を追加
7. probe example で bbox / score / class などを表示
8. 必要なら overlay や raw dump を追加

出力が float tensor の場合は、`UINT8` 前提の text detection parser とは別 parser にします。出力 byte列を `float32` として読むには、alignment と endianness、HAILO output format を確認してください。

## 12. 性能上の注意

raw output が大きいモデルでは、CPU postprocess も重くなります。

今回の text detection 例:

```text
input  = 960 * 544 * 3 = 1,566,720 bytes
output = 960 * 544 * 1 =   522,240 bytes
```

full-resolution score map を connected components するため、parser 側で数 ms から十数 ms 程度かかることがあります。

最適化候補:

```text
visited / queue buffer の再利用
allocation 削減
run-length connected components
maxRegions による早期打ち切り
threshold 後の白画素中心の走査
```

最初は正しさと座標確認を優先し、必要になった段階で最適化する方針で十分です。
