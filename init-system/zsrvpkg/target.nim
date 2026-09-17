import std/[os, strutils]
import ./types
import ./state
import ./logger

proc parseCmdlineTokens(s: string): seq[string] =
  ## Dzieli zawartość `/proc/cmdline` na tokeny zgodnie z konwencją jądra
  ## Linuksa: tokeny są rozdzielone spacjami, ale wartość PO `=` może być
  ## ujęta w cudzysłów, żeby zawierać spacje (np.
  ## `BOOT_IMAGE=/vmlinuz root=/dev/sda1 zsrv.target="multi-user"` albo,
  ## bardziej praktycznie, coś w stylu `foo="bar baz"`) -- naiwny
  ## `splitWhitespace()` rozbiłby taką cudzysłowioną wartość na dwa
  ## osobne tokeny.
  result = @[]
  var current = ""
  var inQuotes = false
  var i = 0
  while i < s.len:
    let c = s[i]
    if c == '"':
      inQuotes = not inQuotes
      inc i
    elif (c == ' ' or c == '\t') and not inQuotes:
      if current.len > 0:
        result.add(current)
        current = ""
      inc i
    else:
      current &= c
      inc i
  if current.len > 0:
    result.add(current)

proc parseTargetToken(value: string): Target =
  case value
  of "rescue": tgRescue
  of "multi-user": tgMultiUser
  else:
    log("zsrv: nieznany target: '" & value & "'")
    tgMultiUser

proc detectTargetFromCmdline*(): Target =
  ## Odczytuje `/proc/cmdline` w poszukiwaniu `zsrv.target=...` (z pełnym
  ## wsparciem dla cudzysłowionych wartości, patrz `parseCmdlineTokens`),
  ## z fallbackiem na argumenty programu (skanowane WSZYSTKIE, nie tylko
  ## pierwszy -- `zsrv --debug --target=rescue` musiało by wcześniej
  ## trafić dokładnie jako pierwszy argument, inaczej fallback cicho nie
  ## zadziałał), a domyślnie `multi-user`.
  try:
    let cmdline = readFile("/proc/cmdline")
    for token in parseCmdlineTokens(cmdline):
      if token.startsWith("zsrv.target="):
        return parseTargetToken(token.split('=', 1)[1])
  except IOError:
    discard # /proc może nie być jeszcze zamontowane — nie jest to błąd krytyczny

  for i in 1 .. paramCount():
    let arg = paramStr(i)
    if arg.startsWith("--target="):
      return parseTargetToken(arg.split('=', 1)[1])

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
