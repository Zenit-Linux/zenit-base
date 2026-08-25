import std/os
import zsrvpkg/[types, state, log, parser, target, eventloop]

const Version = "0.4.0"

when isMainModule:
  if paramCount() >= 1 and paramStr(1) in ["-v", "--version"]:
    echo "zsrv " & Version
    quit(0)

  if getpid().int != 1:
    stderr.writeLine("zsrv: ostrzeżenie — proces nie jest PID 1 (tryb testowy?)")
    # W trybie deweloperskim pozwalamy uruchomić się jako zwykły proces,
    # aby móc testować logikę bez faktycznego bycia init systemem.

  currentTarget = detectTargetFromCmdline()
  log("zsrv " & Version & " — uruchamianie w targecie '" & $currentTarget & "'...")
  loadServices(ServiceDir)
  mainLoop()
