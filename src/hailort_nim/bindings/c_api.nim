# hailort_lowlevel.nim
const libHailoRt =
  when defined(windows): "hailort.dll"
  elif defined(macosx): "libhailort.dylib"
  else: "libhailort.so"

{.push dynlib: libHailoRt.}
include ./generated/hailort_lowlevel_gen
{.pop.}
