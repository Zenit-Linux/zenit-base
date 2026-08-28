import std/posix
import ./lexer
import ./parser
import ./exec
import ./state
import ./vars

proc runLine*(line: string): int =
  let tokens = tokenize(line)
  let statements = splitStatements(tokens)

  var code = 0
  var skipDueToShortCircuit = false

  for stmt in statements:
    if skipDueToShortCircuit:
      skipDueToShortCircuit = false
      continue

    code = runPipeline(stmt)
    lastExitCode = code

    case stmt.sepAfter
    of sepAnd:
      # `&&`: następna instrukcja wykonuje się tylko, gdy ta się powiodła.
      skipDueToShortCircuit = (code != 0)
    of sepOr:
      # `||`: następna instrukcja wykonuje się tylko, gdy ta zawiodła.
      skipDueToShortCircuit = (code == 0)
    of sepSeq, sepNone:
      discard

  code

proc captureCommandOutput(cmd: string): string =
  ## Uruchamia `cmd` przez pełny cykl runLine (więc obsługuje potoki,
  ## przekierowania, wbudowane polecenia — wszystko, co normalna linia
  ## zesh), ale z STDOUT_FILENO tymczasowo przekierowanym na potok, żeby
  ## przechwycić wyjście zamiast wypisać je na terminal. Standardowe
  ## POSIX zachowanie: końcowe znaki nowej linii są usuwane z wyniku.
  var pfd: array[2, cint]
  if pipe(pfd) != 0:
    return ""

  let savedStdout = dup(STDOUT_FILENO)
  discard dup2(pfd[1], STDOUT_FILENO)
  discard close(pfd[1])

  discard runLine(cmd)

  stdout.flushFile()
  discard dup2(savedStdout, STDOUT_FILENO)
  discard close(savedStdout)

  var output = ""
  var buf: array[4096, uint8]
  while true:
    let n = read(pfd[0], addr buf[0], buf.len)
    if n <= 0:
      break
    var chunk = newString(n)
    copyMem(addr chunk[0], addr buf[0], n)
    output.add(chunk)
  discard close(pfd[0])

  # POSIX: usuń WSZYSTKIE końcowe znaki nowej linii z wyniku substytucji.
  while output.len > 0 and output[^1] == '\n':
    output.setLen(output.len - 1)
  output

proc setupCommandSubstitution*() =
  ## Wywoływane raz przy starcie zesh (patrz zesh.nim). Wstrzykuje
  ## `captureCommandOutput` jako implementację `$(...)` w zeshpkg/vars —
  ## patrz komentarz w vars.nim o tym, czemu nie da się tego zrobić przez
  ## zwykły import (cykl: vars -> interpreter -> lexer -> vars).
  commandSubstitutionHook = captureCommandOutput
