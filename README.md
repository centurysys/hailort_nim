# hailort_nim

Unofficial Nim bindings and high-level API for HailoRT.

🇯🇵 Japanese version → README.ja.md

---

## Why?

- Python is convenient, but heavy
- C++ works, but CMake is painful
- Simple inference requires too much boilerplate

`hailort_nim` focuses on minimal, readable inference.

---

## Example (High-level API)

```nim
import hailort_nim

let det = Detector.open("model.hef").get
let res = det.detectNmsByClass(input).get

for d in res:
  echo d.classId, " ", d.score
```

---

## Example Output

```
Input frame size:  1228800
Output frame size: 160320
Detection count: 1
[ 0] class=16 label=dog             score=0.8432 box=(0.0045, 0.0242, 1.0003, 0.9705)
```

---

## Included Example

Input image:

![dog](examples/dog.jpg)

---

## Convert Image to Raw

```bash
convert dog.jpg -resize 640x640! rgb:dog.raw
```

---

## Examples

### High-level (recommended)

```
nim c -r examples/infer_high_ex1.nim -- model.hef examples/dog.raw
```

### Low-level (debug)

```
nim c -r examples/infer_raw.nim -- model.hef examples/dog.raw
```

---

## Project Structure

- bindings/      → auto-generated C bindings
- lowlevel/      → thin wrappers
- highlevel/     → Detector API
- postprocess/   → NMS parsing

---

## Status

- YOLO inference: working
- Detector API: working
- NMS parsing: working

---

## License

MIT

---

## Disclaimer

Unofficial project. Not affiliated with Hailo.
