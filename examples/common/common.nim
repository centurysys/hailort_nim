import std/strformat
import results
import ../../src/hailort_nim

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc fail*(msg: string) {.noreturn.} =
  stderr.writeLine(msg)
  quit(1)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc getOrFail*[T](res: HE[T], what: string): T =
  if res.isErr:
    fail(&"{what}: {res.error}")
  result = res.get

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc checkOrFail*(res: HE[void], what: string) =
  if res.isErr:
    fail(&"{what}: {res.error}")

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc loadRaw*(path: string): seq[byte] =
  let s = readFile(path)
  result = newSeq[byte](s.len)
  if s.len > 0:
    copyMem(addr result[0], unsafeAddr s[0], s.len)
