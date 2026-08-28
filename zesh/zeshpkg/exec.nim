import std/[posix, terminal, strutils, tables]
import ./parser
import ./state
import ./vars
import ./builtins
import ./jobcontrol

proc applyRedirects(r: Redirect) =
  ## Wywoływane W PROCESIE POTOMNYM, po fork(), przed execvp().
  if r.stdinFile.len > 0:
    let fd = posix.open(r.stdinFile.cstring, O_RDONLY)
    if fd < 0:
      stderr.writeLine("zesh: nie mozna otworzyc '" & r.stdinFile & "' do odczytu")
      quit(1)
    discard dup2(fd, STDIN_FILENO)
    discard close(fd)

  if r.stdoutFile.len > 0:
    let flags = O_WRONLY or O_CREAT or (if r.appendOut: O_APPEND else: O_TRUNC)
    let fd = posix.open(r.stdoutFile.cstring, flags, 0o644)
    if fd < 0:
      stderr.writeLine("zesh: nie mozna otworzyc '" & r.stdoutFile & "' do zapisu")
      quit(1)
    discard dup2(fd, STDOUT_FILENO)
    discard close(fd)

proc resolveAlias(argv: seq[string]): seq[string] =
  ## Podmienia pierwsze słowo poleceniem z `alias`, jeśli takie istnieje.
  ## TODO: rekurencyjne rozwijanie aliasów (dziś tylko jeden poziom, co
  ## chroni przed nieskończoną pętlą przy aliasie odwołującym się do siebie).
  if argv.len == 0 or not aliases.hasKey(argv[0]):
    return argv
  let expansion = aliases[argv[0]].splitWhitespace()
  expansion & argv[1..^1]

proc execCommand(cmd: Command) {.noreturn.} =
  ## Wywoływane W PROCESIE POTOMNYM: ustawia przekierowania i wykonuje
  ## polecenie zewnętrzne. Nie wraca (execvp albo quit).
  applyRedirects(cmd.redirect)
  let argv = resolveAlias(cmd.argv)
  if argv.len == 0:
    quit(0)
  let cArgs = allocCStringArray(argv)
  discard execvp(argv[0].cstring, cArgs)
  stderr.writeLine("zesh: polecenie nie znalezione: " & argv[0])
  quit(127)

proc forkPipeline(pipeline: Pipeline): seq[Pid] =
  ## Uruchamia potok poleceń zewnętrznych łącząc je przez pipe()+fork(),
  ## zwracając PID-y wszystkich stopni potoku (bez czekania na nie —
  ## czekanie to odpowiedzialność wywołującego, w trybie fg albo bg).
  result = @[]
  var prevReadEnd: cint = -1

  for idx, cmd in pipeline:
    var pfd: array[2, cint]
    let hasNext = idx < pipeline.len - 1
    if hasNext:
      if pipe(pfd) != 0:
        stderr.styledWriteLine(fgRed, "zesh: pipe() nie powiodlo sie")
        return @[]

    let pid = fork()
    if pid < 0:
      stderr.styledWriteLine(fgRed, "zesh: fork() nie powiodlo sie")
      return @[]

    if pid == 0:
      if prevReadEnd != -1:
        discard dup2(prevReadEnd, STDIN_FILENO)
        discard close(prevReadEnd)
      if hasNext:
        discard close(pfd[0])
        discard dup2(pfd[1], STDOUT_FILENO)
        discard close(pfd[1])
      execCommand(cmd)
      # execCommand nie wraca.

    result.add(pid)
    if prevReadEnd != -1:
      discard close(prevReadEnd)
    if hasNext:
      discard close(pfd[1])
      prevReadEnd = pfd[0]
    else:
      prevReadEnd = -1

proc pipelineToString(pipeline: Pipeline): string =
  var parts: seq[string] = @[]
  for cmd in pipeline:
    parts.add(cmd.argv.join(" "))
  parts.join(" | ")

proc runPipeline*(stmt: Statement): int =
  let pipeline = stmt.pipeline
  if pipeline.len == 0:
    return 0

  # Pojedyncze polecenie bez potoku: sprawdź, czy to przypisanie zmiennej
  # lokalnej albo builtin, zanim uruchomimy nowy proces. Builtiny nie mogą
  # sensownie działać w tle (nie ma czego forkować) — traktujemy `builtin &`
  # jak zwykłe wywołanie synchroniczne.
  if pipeline.len == 1:
    let cmd = pipeline[0]
    if cmd.argv.len == 0:
      return 0

    if cmd.argv.len == 1 and isAssignment(cmd.argv[0]):
      let parts = cmd.argv[0].split('=', 1)
      localVars[parts[0]] = parts[1]
      return 0

    let (handled, code) = runBuiltin(cmd.argv[0], cmd.argv[1..^1])
    if handled:
      return code

  let pids = forkPipeline(pipeline)
  if pids.len == 0:
    return 1

  if stmt.background:
    discard addJob(pids, pipelineToString(pipeline))
    return 0

  # Czekamy na wszystkie stopnie potoku; kod wyjścia całego potoku to kod
  # OSTATNIEGO polecenia (zgodnie z konwencją powłok uniksowych).
  var finalStatus = 0
  for i, pid in pids:
    var status: cint
    discard waitpid(pid, status, 0)
    if i == pids.len - 1 and WIFEXITED(status):
      finalStatus = WEXITSTATUS(status)

  finalStatus
