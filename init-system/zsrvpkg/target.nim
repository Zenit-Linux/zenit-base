import std/[os, strutils]
import ./types
import ./log

proc detectTargetFromCmdline*(): Target =
  ## Odczytuje `/proc/cmdline` w poszukiwaniu `zsrv.target=...`, z
  ## fallbackiem na argument programu, a domyślnie `multi-user`.
  ## TODO: pełny parser cmdline (dziś prosty `split`/`startsWith`).
  try:
    let cmdline = readFile("/proc/cmdline")
    for token in cmdline.splitWhitespace():
      if token.startsWith("zsrv.target="):
        let value = token.split('=', 1)[1]
        case value
        of "rescue": return tgRescue
        of "multi-user": return tgMultiUser
        else: log("zsrv: nieznany target w /proc/cmdline: '" & value & "'")
  except IOError:
    discard # /proc może nie być jeszcze zamontowane — nie jest to błąd krytyczny

  if paramCount() >= 1 and paramStr(1).startsWith("--target="):
    case paramStr(1).split('=', 1)[1]
    of "rescue": return tgRescue
    of "multi-user": return tgMultiUser
    else: discard

  tgMultiUser
