import std/algorithm

type
  Detection* = object
    classId*: int
    score*: float32
    yMin*: float32
    xMin*: float32
    yMax*: float32
    xMax*: float32

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc sortByScoreDesc*(detections: var seq[Detection]) =
  detections.sort(proc(a, b: Detection): int = cmp(b.score, a.score))

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc filterByScore*(detections: seq[Detection], threshold: float32): seq[Detection] =
  result = newSeqOfCap[Detection](detections.len)
  for d in detections:
    if d.score >= threshold:
      result.add(d)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc clamp01*(x: float32): float32 =
  if x < 0.0'f32:
    return 0.0'f32
  if x > 1.0'f32:
    return 1.0'f32
  result = x

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc clamped*(d: Detection): Detection =
  result = d
  result.yMin = clamp01(result.yMin)
  result.xMin = clamp01(result.xMin)
  result.yMax = clamp01(result.yMax)
  result.xMax = clamp01(result.xMax)
