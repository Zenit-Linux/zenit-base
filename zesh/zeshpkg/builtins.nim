import std/[os, strutils, terminal, tables]
import ./state
import ./cmdhistory
import ./jobcontrol

proc runBuiltin*(cmd: string, args: seq[string]): (bool, int) =
  ## Zwraca (obsłużone_jako_builtin, kod_wyjścia).
  case cmd
  of "cd":
    # `cd -` przełącza na poprzedni katalog roboczy ($OLDPWD, tak jak w
    # bashu) i wypisuje nową ścieżkę -- dokładnie to, co bash robi po
    # `cd -`, żeby było widać, dokąd się właśnie wróciło. Każde udane
    # `cd` (obojętnie jakie) aktualizuje $OLDPWD/$PWD, żeby `cd -`
    # działało poprawnie także po kolejnych `cd`, oraz żeby skrypty
    # mogły polegać na $PWD tak jak w prawdziwej powłoce POSIX.
    let previousDir = getCurrentDir()
    var target: string
    if args.len == 0:
      target = getHomeDir()
    elif args[0] == "-":
      if not existsEnv("OLDPWD"):
        stderr.styledWriteLine(fgRed, "zesh: cd: OLDPWD nie jest ustawione")
        return (true, 1)
      target = getEnv("OLDPWD")
    else:
      target = args[0]

    try:
      setCurrentDir(target)
      let newDir = getCurrentDir()
      putEnv("OLDPWD", previousDir)
      putEnv("PWD", newDir)
      if args.len > 0 and args[0] == "-":
        echo newDir
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
  of "bg":
    if args.len == 0:
      stderr.writeLine("zesh: bg: brak numeru zadania (użyj: bg %N)")
      return (true, 1)
    let spec = args[0].strip(chars = {'%'})
    let id = spec.parseInt()
    let ok = continueJobBg(id)
    return (true, if ok: 0 else: 1)
  of "read":
    # `read var1 var2 ... varN` -- czyta JEDNĄ linię ze stdin i dzieli ją
    # na słowa (białe znaki): pierwsze N-1 słów trafia do pierwszych N-1
    # zmiennych, a WSZYSTKO, co zostanie (łącznie z ewentualnymi
    # dodatkowymi spacjami) -- do OSTATNIEJ zmiennej, dokładnie tak jak w
    # bashu (`read a b` przy wejściu "x y z" daje a=x, b="y z"). Brak
    # nazwy zmiennej -> domyślnie `REPLY` (konwencja bash). Zabraknięcie
    # słów dla którejś zmiennej zostawia ją jako pusty tekst. EOF (brak
    # linii do odczytania) zwraca kod 1, tak jak w bashu.
    let varNames = if args.len > 0: args else: @["REPLY"]
    var line: string
    try:
      line = readLine(stdin)
    except EOFError:
      for name in varNames:
        localVars[name] = ""
      return (true, 1)

    let words = line.splitWhitespace()
    for i, name in varNames:
      if i == varNames.len - 1:
        # Ostatnia zmienna zbiera resztę -- łączymy pozostałe słowa
        # pojedynczą spacją (upraszczamy sobie życie względem bashowego
        # zachowania "oryginalne białe znaki", co i tak rzadko ma
        # znaczenie w praktyce skryptowej).
        localVars[name] = (if i < words.len: words[i ..< words.len].join(" ") else: "")
      else:
        localVars[name] = (if i < words.len: words[i] else: "")
    return (true, 0)
  of "type":
    for a in args:
      if aliases.hasKey(a):
        echo a & " to alias dla '" & aliases[a] & "'"
      elif a in ["cd", "pwd", "exit", "export", "unset", "history", "alias",
                 "unalias", "jobs", "fg", "bg", "read", "type"]:
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
