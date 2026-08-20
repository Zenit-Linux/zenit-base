import std/[os, times, parseopt, terminal]

const VERSION = "1.0.0"

proc printUsage() =
  echo "mk — nowoczesna alternatywa dla touch (Zenith Linux)"
  echo ""
  echo "Użycie: mk [opcje] PLIK..."
  echo ""
  echo "Opcje:"
  echo "  -c, --no-create      nie twórz pliku, jeśli nie istnieje"
  echo "  -v, --verbose        wypisuj utworzone/zaktualizowane pliki"
  echo "  -h, --help           pokaż tę pomoc"
  echo "      --version        pokaż wersję"

var
  noCreate = false
  verbose = false
  files: seq[string] = @[]

var p = initOptParser()
for kind, key, val in p.getopt():
  case kind
  of cmdArgument: files.add(key)
  of cmdLongOption, cmdShortOption:
    case key
    of "c", "no-create": noCreate = true
    of "v", "verbose": verbose = true
    of "h", "help":
      printUsage()
      quit(0)
    of "version":
      echo "mk " & VERSION
      quit(0)
    else: discard
  of cmdEnd: discard

if files.len == 0:
  stderr.styledWriteLine(fgRed, "mk: brak argumentu — podaj nazwę pliku")
  quit(1)

var exitCode = 0
let now = getTime()

for f in files:
  var justCreated = false
  if not fileExists(f):
    if noCreate:
      continue
    try:
      writeFile(f, "")
      justCreated = true
    except OSError as e:
      stderr.styledWriteLine(fgRed, "mk: nie można utworzyć '", f, "': ", e.msg)
      exitCode = 1
      continue

  try:
    setLastModificationTime(f, now)
    if verbose:
      if justCreated:
        stdout.styledWriteLine(fgGreen, "mk: utworzono plik '", f, "'")
      else:
        stdout.styledWriteLine(fgCyan, "mk: zaktualizowano znacznik czasu '", f, "'")
  except OSError as e:
    stderr.styledWriteLine(fgRed, "mk: błąd aktualizacji czasu '", f, "': ", e.msg)
    exitCode = 1

quit(exitCode)
