import std/[os, terminal, strutils]
import zeshpkg/[state, history, jobs, interpreter, prompt]

const Version = "0.3.0"

when isMainModule:
  if paramCount() >= 1 and paramStr(1) in ["-v", "--version"]:
    echo "zesh " & Version
    quit(0)

  echo "zesh " & Version & " — natywna powłoka Zenith Linux"
  loadHistory()

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

    line = expandHistoryRefs(line)
    history.add(line)

    lastExitCode = runLine(line)

  saveHistory()
