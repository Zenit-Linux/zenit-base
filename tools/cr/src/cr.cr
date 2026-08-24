import std/[os, strutils, terminal, parseopt]

const VERSION = "1.0.0"

proc printUsage() =
  echo "cr — nowoczesna alternatywa dla mkdir (Zenith Linux)"
  echo ""
  echo "Użycie: cr [opcje] KATALOG..."
  echo ""
  echo "Opcje:"
  echo "  -p, --parents        twórz katalogi nadrzędne w razie potrzeby"
  echo "  -m, --mode=MODE      ustaw uprawnienia (np. 755)"
  echo "  -v, --verbose        wypisuj utworzone katalogi"
  echo "  -h, --help           pokaż tę pomoc"
  echo "      --version        pokaż wersję"

proc octToPermissions(m: int): set[FilePermission] =
  result = {}
  if (m and 0o400) != 0: result.incl(fpUserRead)
  if (m and 0o200) != 0: result.incl(fpUserWrite)
  if (m and 0o100) != 0: result.incl(fpUserExec)
  if (m and 0o040) != 0: result.incl(fpGroupRead)
  if (m and 0o020) != 0: result.incl(fpGroupWrite)
  if (m and 0o010) != 0: result.incl(fpGroupExec)
  if (m and 0o004) != 0: result.incl(fpOthersRead)
  if (m and 0o002) != 0: result.incl(fpOthersWrite)
  if (m and 0o001) != 0: result.incl(fpOthersExec)

var
  parents = false
  verbose = false
  mode = ""
  dirs: seq[string] = @[]

var p = initOptParser()
for kind, key, val in p.getopt():
  case kind
  of cmdArgument:
    dirs.add(key)
  of cmdLongOption, cmdShortOption:
    case key
    of "p", "parents": parents = true
    of "v", "verbose": verbose = true
    of "m", "mode": mode = val
    of "h", "help":
      printUsage()
      quit(0)
    of "version":
      echo "cr " & VERSION
      quit(0)
    else: discard
  of cmdEnd: discard

if dirs.len == 0:
  stderr.styledWriteLine(fgRed, "cr: brak argumentu — podaj nazwę katalogu")
  quit(1)

var exitCode = 0

for d in dirs:
  try:
    let parent = parentDir(d)
    if not parents and parent.len > 0 and not dirExists(parent):
      raise newException(OSError, "katalog nadrzędny nie istnieje (użyj -p, aby go utworzyć)")

    createDir(d)

    if mode.len > 0:
      let m = parseOctInt(mode)
      setFilePermissions(d, octToPermissions(m))

    if verbose:
      stdout.styledWriteLine(fgGreen, "cr: utworzono katalog '", d, "'")
  except OSError as e:
    stderr.styledWriteLine(fgRed, "cr: nie można utworzyć katalogu '", d, "': ", e.msg)
    exitCode = 1
  except ValueError:
    stderr.styledWriteLine(fgRed, "cr: nieprawidłowy tryb uprawnień '", mode, "'")
    exitCode = 1

quit(exitCode)
