import std/[os, strutils, terminal, parseopt, times]

const VERSION = "1.0.0"

let trashDir = getHomeDir() / ".zenith" / "trash"

proc printUsage() =
  echo "dl — nowoczesna alternatywa dla rm (Zenith Linux)"
  echo ""
  echo "Użycie: dl [opcje] PLIK/KATALOG..."
  echo ""
  echo "Opcje:"
  echo "  -r, --recursive      usuwaj katalogi rekurencyjnie"
  echo "  -f, --force          nie pytaj, ignoruj brakujące pliki"
  echo "  -i, --interactive    pytaj przed każdym usunięciem"
  echo "      --permanent      usuń trwale, z pominięciem kosza"
  echo "  -v, --verbose        wypisuj usuwane pliki"
  echo "  -h, --help           pokaż tę pomoc"
  echo "      --version        pokaż wersję"
  echo ""
  echo "Domyślnie pliki trafiają do kosza: " & trashDir

var
  recursive = false
  force = false
  interactive = false
  permanent = false
  verbose = false
  targets: seq[string] = @[]

var p = initOptParser()
for kind, key, val in p.getopt():
  case kind
  of cmdArgument: targets.add(key)
  of cmdLongOption, cmdShortOption:
    case key
    of "r", "recursive": recursive = true
    of "f", "force": force = true
    of "i", "interactive": interactive = true
    of "permanent": permanent = true
    of "v", "verbose": verbose = true
    of "h", "help":
      printUsage()
      quit(0)
    of "version":
      echo "dl " & VERSION
      quit(0)
    else: discard
  of cmdEnd: discard

if targets.len == 0:
  stderr.styledWriteLine(fgRed, "dl: brak argumentu — podaj plik lub katalog")
  quit(1)

if not permanent and not dirExists(trashDir):
  createDir(trashDir)

proc confirm(msg: string): bool =
  stdout.write(msg & " [t/N] ")
  stdout.flushFile()
  try:
    let ans = readLine(stdin).strip().toLowerAscii()
    result = ans == "t" or ans == "tak" or ans == "y" or ans == "yes"
  except EOFError:
    result = false

var exitCode = 0

for t in targets:
  let isDir = dirExists(t) and not fileExists(t)
  let isFile = fileExists(t)

  if not isDir and not isFile:
    if not force:
      stderr.styledWriteLine(fgRed, "dl: nie można usunąć '", t, "': nie istnieje")
      exitCode = 1
    continue

  if isDir and not recursive:
    stderr.styledWriteLine(fgRed, "dl: '", t, "' jest katalogiem — użyj -r, aby go usunąć")
    exitCode = 1
    continue

  if interactive and not confirm("dl: usunąć '" & t & "'?"):
    continue

  try:
    if permanent:
      if isDir:
        removeDir(t)
      else:
        removeFile(t)
      if verbose:
        stdout.styledWriteLine(fgYellow, "dl: usunięto trwale '", t, "'")
    else:
      let stamp = $getTime().toUnix()
      let dest = trashDir / (extractFilename(t.strip(chars = {'/'})) & "_" & stamp)
      if isDir:
        moveDir(t, dest)
      else:
        moveFile(t, dest)
      if verbose:
        stdout.styledWriteLine(fgGreen, "dl: przeniesiono do kosza '", t, "' -> '", dest, "'")
  except OSError as e:
    stderr.styledWriteLine(fgRed, "dl: błąd usuwania '", t, "': ", e.msg)
    exitCode = 1

quit(exitCode)
