# hailort_nim

HailoRT のための Nim バインディングおよび高レベルAPI

🇺🇸 English version → README.md

---

## 概要

- Pythonは重い
- C++はCMakeがつらい
- コードが長い

これを解消するためのライブラリです。

---

## サンプル（高レベルAPI）

```nim
import hailort_nim

let det = Detector.open("model.hef").get
let res = det.detectNmsByClass(input).get

for d in res:
  echo d.classId, " ", d.score
```

---

## 実行結果例

```
Input frame size:  1228800
Output frame size: 160320
Detection count: 1
[ 0] class=16 label=dog             score=0.8432 box=(0.0045, 0.0242, 1.0003, 0.9705)
```

---

## サンプル画像

![dog](examples/dog.jpg)

---

## 画像の変換方法

```bash
convert dog.jpg -resize 640x640! rgb:dog.raw
```

---

## 実行方法

### 高レベルAPI

```
nim c -r examples/infer_high_ex1.nim -- model.hef examples/dog.raw
```

### 低レベルAPI

```
nim c -r examples/infer_raw.nim -- model.hef examples/dog.raw
```

---

## 構成

- bindings/      → C API（自動生成）
- lowlevel/      → 薄いラッパ
- highlevel/     → Detector API
- postprocess/   → NMS処理

---

## 状態

- 推論: OK
- NMS: OK
- Detector API: OK

---

## 注意

非公式プロジェクトです。
