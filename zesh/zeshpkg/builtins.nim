import std/[os, strutils, terminal, tables]
import ./state
import ./cmdhistory
import ./jobcontrol

proc runBuiltin*(cmd: string, args: seq[string]): (bool, int) =
  ## Zwraca (obsłużone_jako_builtin, kod_wyjścia).
  case cmd
  of "cd":
    let target = if args.len > 0: args[0] else: getHomeDir()
    try:
      setCurrentDir(target)
      return (true, 0)
    except OSError as e:
      stderr.styledWriteLine(fgRed, "zesh: cd: ", e.msg)
      return (true, 1)
  of "pwd":
    echo getCurrentDir()
    return (true, 0)
  of "exit":
    saveHistory()
    let code = if args.len > 0: parseInt(args[0]) else: 0
    quit(code)
  of "export":
    for a in args:
      let parts = a.split('=', 1)
      if parts.len == 2:
        putEnv(parts[0], parts[1])
        localVars.del(parts[0]) # eksportowana zmienna przestaje być "tylko lokalna"
      elif localVars.hasKey(a):
        putEnv(a, localVars[a])
    return (true, 0)
  of "unset":
    for a in args:
      localVars.del(a)
      if existsEnv(a): delEnv(a)
    return (true, 0)
  of "history":
    for idx, h in history:
      echo align($(idx + 1), 4) & "  " & h
    return (true, 0)
  of "alias":
    if args.len == 0:
      for name, value in aliases:
        echo name & "='" & value & "'"
      return (true, 0)
    for a in args:
      let parts = a.split('=', 1)
      if parts.len == 2:
        aliases[parts[0]] = parts[1]
      else:
        if aliases.hasKey(a):
          echo a & "='" & aliases[a] & "'"
    return (true, 0)
  of "unalias":
    for a in args:
      aliases.del(a)
    return (true, 0)
  of "jobs":
    listJobs()
    return (true, 0)
  of "fg":
    if args.len == 0:
      stderr.writeLine("zesh: fg: brak numeru zadania (użyj: fg %N)")
      return (true, 1)
    let spec = args[0].strip(chars = {'%'})
    let id = spec.parseInt()
    waitForJob(id)
    return (true, 0)
  of "type":
    for a in args:
      if aliases.hasKey(a):
        echo a & " to alias dla '" & aliases[a] & "'"
      elif a in ["cd", "pwd", "exit", "export", "unset", "history", "alias",
                 "unalias", "jobs", "fg", "type"]:
        echo a & " jest poleceniem wbudowanym zesh"
      else:
        let path = findExe(a)
        if path.len > 0:
          echo a & " to " & path
        else:
          echo "zesh: type: nie znaleziono '" & a & "'"
    return (true, 0)
  else:
    return (false, 0)
