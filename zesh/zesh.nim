import std/[os, osproc, strutils, terminal]

const VERSION = "0.1.0"

proc promptPath(): string =
  let cwd = getCurrentDir()
  let home = getHomeDir()
  if cwd == home:
    result = "~"
  elif cwd.startsWith(home & "/"):
    result = "~" & cwd[home.len .. ^1]
  else:
    result = cwd

proc expandVars(s: string): string =
  result = s
  for key, val in envPairs():
    result = result.replace("$" & key, val)
    result = result.replace("${" & key & "}", val)

proc isSimple(line: string): bool =
  not line.contains('|') and not line.contains('>') and not line.contains('<') and
    not line.contains('&') and not line.contains(';')

proc runBuiltin(cmd: string, args: seq[string]): bool =
  ## Zwraca true, jeśli polecenie było wbudowane i zostało obsłużone.
  case cmd
  of "cd":
    let target = if args.len > 0: args[0] else: getHomeDir()
    try:
      setCurrentDir(target)
    except OSError as e:
      stderr.styledWriteLine(fgRed, "zesh: cd: ", e.msg)
    return true
  of "pwd":
    echo getCurrentDir()
    return true
  of "exit":
    let code = if args.len > 0: parseInt(args[0]) else: 0
    quit(code)
  of "export":
    for a in args:
      let parts = a.split('=', 1)
      if parts.len == 2:
        putEnv(parts[0], parts[1])
    return true
  else:
    return false

proc runSimple(cmdline: string): int =
  let parts = cmdline.splitWhitespace()
  if parts.len == 0: return 0
  let cmd = parts[0]
  let args = if parts.len > 1: parts[1..^1] else: @[]

  if runBuiltin(cmd, args):
    return 0

  try:
    let p = startProcess(cmd, args = args, options = {poParentStreams, poUsePath})
    result = p.waitForExit()
    p.close()
  except OSError:
    stderr.styledWriteLine(fgRed, "zesh: polecenie nie znalezione: ", cmd)
    result = 127

proc runLine(line: string): int =
  if isSimple(line):
    result = runSimple(line)
  else:
    # Złożone konstrukcje (potoki, przekierowania, sekwencje) — deleguj do /bin/sh
    # do czasu ukończenia natywnego silnika potoków zesh.
    result = execCmd(line)

when isMainModule:
  if paramCount() >= 1 and paramStr(1) in ["-v", "--version"]:
    echo "zesh " & VERSION
    quit(0)

  echo "zesh " & VERSION & " — nowoczesna powłoka Zenith Linux"

  while true:
    stdout.styledWrite(fgMagenta, styleBright, "zesh")
    stdout.styledWrite(fgDefault, resetStyle, " ")
    stdout.styledWrite(fgCyan, promptPath())
    stdout.styledWrite(fgDefault, resetStyle, " ❯ ")
    stdout.flushFile()

    var line: string
    try:
      line = readLine(stdin)
    except EOFError:
      echo ""
      break

    line = line.strip()
    if line.len == 0: continue

    let expanded = expandVars(line)
    discard runLine(expanded)
