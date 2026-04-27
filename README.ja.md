# hailort_nim

## 概要

`hailort_nim` は HailoRT の Nim バインディングです。

- ゼロコピー志向
- 低遅延推論
- 明示的なリソース管理
- 組み込み・エッジ用途向け設計

---

# 🚀 クイックスタート

YOLOで物体検出：

```nim
let detector = Detector.open("yolov11n.hef").get()
let detections = detector.detectNmsByClassAuto(input).get()

echo detections[0].classId
```

出力例：

```text
dog
```

📷 サンプル画像：
![dog](examples/dog.jpg)

---

# ⚠️ 重要: open/close をループで使わない

❌ NG例：

```nim
for frame in stream:
  let d = Detector.open("model.hef")
  d.detect(...)
  d.close()
```

問題：

- SRAMが解放されず蓄積
- 最終的にエラー：
  - HAILO_OUT_OF_PHYSICAL_DEVICES
  - SRAM_FULL

---

# ✅ 新機能: 高速モデル切替 (activate/deactivate)

## コンセプト

```text
openPrepared（1回）→ activate → 推論 → deactivate
```

## 使用例

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

# ⏱ パフォーマンス

(HAILO-8L + YOLOv11n)

| 処理 | 時間 |
|------|------|
| prepare | 約150〜400 ms |
| activate | 約2〜3 ms |
| deactivate | 約1 ms |
| 推論 | 約30 ms |

👉 モデル切替は「ロード」ではなく

```text
コンテキスト切替のみ
```

---

# 🧠 モデル常駐数

テスト結果：

- yolov11n.hef (~12MB)
- 最大12モデル常駐可能

※ 注意

- HEFサイズ ≠ 実メモリ使用量
- Hailoはストリーミング実行

---

# 🧩 API概要

## 単一モデル

```nim
Detector.open()
```

## 複数モデル

```nim
Detector.openPrepared()
activate()
deactivate()
```

---

# 🎯 設計思想

```text
一度ロードして使い回す
```

---

# まとめ

- クイックスタートはそのまま使える
- ループでopen/closeは絶対NG
- マルチモデルはactivate切替

→ 安定・高速に動作
