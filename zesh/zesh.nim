import std/[os, terminal, strutils]
import zeshpkg/[state, cmdhistory, jobcontrol, interpreter, prompt]

const Version = "0.2.0"

proc printUsage() =
  echo "zesh " & Version & " — natywna powłoka Zenit Linux"
  echo ""
  echo "Użycie:"
  echo "  zesh                    tryb interaktywny (REPL)"
  echo "  zesh -c 'POLECENIE' [NAZWA [ARG...]]"
  echo "                          wykonuje POLECENIE (przez pełny runLine) i kończy pracę;"
  echo "                          NAZWA/ARG... ustawiają $0/$1.. jak w 'sh -c'"
  echo "  zesh SKRYPT [ARG...]    wykonuje linie SKRYPTU po kolei, nieinteraktywnie;"
  echo "                          ARG... dostępne w skrypcie jako $1, $2, ... ($0 = SKRYPT, $# = liczba ARG)"
  echo "  zesh -v | --version     wypisuje wersję"
  echo "  zesh -h | --help        wypisuje tę pomoc"

proc runScriptFile(path: string): int =
  ## Wykonuje plik linia po linii przez pełny `runLine` (te same potoki,
  ## przekierowania, wbudowane polecenia i substytucje co w trybie
  ## interaktywnym) — bez wypisywania promptu ani zapisywania do historii
  ## poleceń, bo to tryb nieinteraktywny (patrz `shellIsInteractive` w
  ## zeshpkg/jobcontrol, które samo wykrywa brak terminala i odpowiednio
  ## się wycisza).
  ##
  ## Puste linie i linie zaczynające się od `#` (po obcięciu białych
  ## znaków z lewej) są pomijane, tak jak komentarze w skryptach powłoki
  ## POSIX.
  ##
  ## Parametry pozycyjne (`$0`, `$1`..`$9`, `$@`, `$#`) są ustawiane przez
  ## wywołującego (`zesh.nim`, blok `isMainModule`) PRZED wywołaniem tej
  ## funkcji — patrz `zeshpkg/state.scriptName`/`scriptArgs` i ich
  ## odczyt w `zeshpkg/vars.expandVars`.
  var content: string
  try:
    content = readFile(path)
  except IOError:
    stderr.writeLine("zesh: nie mozna odczytac skryptu '" & path & "'")
    return 1

  var code = 0
  for rawLine in content.splitLines():
    let line = rawLine.strip()
    if line.len == 0 or line.startsWith("#"):
      continue
    code = runLine(line)
    lastExitCode = code

  code

when isMainModule:
  if paramCount() >= 1 and paramStr(1) in ["-v", "--version"]:
    echo "zesh " & Version
    quit(0)

  if paramCount() >= 1 and paramStr(1) in ["-h", "--help"]:
    printUsage()
    quit(0)

  if paramCount() >= 1 and paramStr(1) == "-c":
    if paramCount() < 2:
      stderr.writeLine("zesh: opcja -c wymaga argumentu z poleceniem")
      quit(2)
    initJobControl()
    setupCommandSubstitution()
    # Zgodnie z konwencją `sh -c polecenie nazwa arg1 arg2 ...`: pierwszy
    # argument PO poleceniu (jeśli podany) staje się $0, a kolejne $1, $2...
    if paramCount() >= 3:
      scriptName = paramStr(3)
      for k in 4 .. paramCount():
        scriptArgs.add(paramStr(k))
    quit(runLine(paramStr(2)))

  if paramCount() >= 1:
    # Argument nie zaczynający się od '-' i niebędący znaną opcją wyżej
    # jest traktowany jako ścieżka do skryptu do wykonania (tryb
    # nieinteraktywny), dokładnie tak jak `sh SKRYPT` w powłokach POSIX.
    # Kolejne argumenty ($2, $3, ...) trafiają do skryptu jako $1, $2...
    initJobControl()
    setupCommandSubstitution()
    scriptName = paramStr(1)
    for k in 2 .. paramCount():
      scriptArgs.add(paramStr(k))
    quit(runScriptFile(paramStr(1)))

  echo "zesh " & Version & " — natywna powłoka Zenit Linux"
  initJobControl()
  loadHistory()
  setupCommandSubstitution()

  while true:
    refreshJobStatuses()

    stdout.styledWrite(fgMagenta, styleBright, "zesh")
    stdout.styledWrite(fgDefault, resetStyle, " ")
    stdout.styledWrite(fgCyan, promptPath())
    stdout.styledWrite(fgDefault, resetStyle, promptMarker(lastExitCode))
    stdout.flushFile()

    var line: string
    try:
      line = readLine(stdin)
    except EOFError:
      echo ""
      break

    line = line.strip()
    if line.len == 0: continue

    let (expanded, ok) = expandHistoryRefs(line)
    if not ok: continue
    line = expanded
    history.add(line)

    lastExitCode = runLine(line)

  saveHistory()
