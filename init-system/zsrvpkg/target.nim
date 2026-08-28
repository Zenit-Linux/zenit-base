import std/[os, strutils]
import ./types
import ./state
import ./logger

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

const RuntimeTargetFile = "/run/zenit/target"

proc readRuntimeTargetOverride*(): Target =
  ## Odczytuje `/run/zenit/target` (jeśli istnieje) jako mechanizm
  ## przełączania targetu W LOCIE, bez ponownego rozruchu — operator albo
  ## przyszłe narzędzie `zsrvctl isolate TARGET` może nadpisać ten plik i
  ## wysłać `kill -HUP 1`, żeby zsrv przeszedł np. z multi-user na rescue
  ## (co zatrzyma usługi spoza nowego targetu — patrz supervisor.applyTarget).
  ## Zwraca bieżący `currentTarget`, jeśli plik nie istnieje albo ma
  ## nierozpoznaną zawartość (brak zmiany).
  if not fileExists(RuntimeTargetFile):
    return currentTarget

  try:
    let value = readFile(RuntimeTargetFile).strip()
    case value
    of "rescue": return tgRescue
    of "multi-user": return tgMultiUser
    else:
      log("zsrv: nieznany target w " & RuntimeTargetFile & ": '" & value & "'")
      return currentTarget
  except IOError:
    return currentTarget
