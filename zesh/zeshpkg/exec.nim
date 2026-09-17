import std/[posix, terminal, strutils, tables, sets]
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

  if r.stderrFile.len > 0:
    let flags = O_WRONLY or O_CREAT or (if r.appendErr: O_APPEND else: O_TRUNC)
    let fd = posix.open(r.stderrFile.cstring, flags, 0o644)
    if fd < 0:
      stderr.writeLine("zesh: nie mozna otworzyc '" & r.stderrFile & "' do zapisu")
      quit(1)
    discard dup2(fd, STDERR_FILENO)
    discard close(fd)

  # `2>&1` MUSI być zastosowane PO ewentualnym `>plik` powyżej — bierzemy
  # deskryptor STDOUT_FILENO taki, jaki jest w TYM momencie (a więc już
  # po jego własnym przekierowaniu, jeśli było), dokładnie tak, jak robi
  # to prawdziwa powłoka POSIX z kolejnością przekierowań czytaną od lewej
  # do prawej.
  if r.mergeErrToOut:
    discard dup2(STDOUT_FILENO, STDERR_FILENO)

proc resolveAlias(argv: seq[string]): seq[string] =
  ## Podmienia pierwsze słowo poleceniem z `alias`, REKURENCYJNIE (alias
  ## może rozwijać się do innego aliasu), z ochroną przed nieskończoną
  ## pętlą, gdy alias (pośrednio) odwołuje się sam do siebie -- np.
  ## `alias ls='ls --color'` MUSI zatrzymać się po jednym rozwinięciu
  ## (drugie słowo, "ls", jest identyczne z pierwszym, ale to wciąż to
  ## samo polecenie zewnętrzne `ls`, nie kolejny alias do rozwinięcia --
  ## rozpoznajemy to po tym, że dana nazwa była już RAZ podmieniona w tym
  ## łańcuchu). Zestaw już-podmienionych nazw pilnuje tego bez względu na
  ## to, jak długi/zapętlony jest łańcuch.
  var current = argv
  var seen = initHashSet[string]()
  while current.len > 0 and aliases.hasKey(current[0]) and current[0] notin seen:
    seen.incl(current[0])
    let expansion = aliases[current[0]].splitWhitespace()
    current = expansion & current[1..^1]
  current

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

proc resetChildSignals() =
  ## Wywoływane W PROCESIE POTOMNYM zaraz po fork(), przed execvp().
  ## zesh (proces rodzica) ignoruje SIGINT/SIGQUIT/SIGTSTP/SIGTTIN/SIGTTOU
  ## (patrz jobcontrol.initJobControl) — bez przywrócenia domyślnej
  ## obsługi te ustawienia odziedziczyłby też każdy uruchomiony program,
  ## więc np. Ctrl+C w ogóle by go nie przerywało.
  signal(SIGINT, SIG_DFL)
  signal(SIGQUIT, SIG_DFL)
  signal(SIGTSTP, SIG_DFL)
  signal(SIGTTIN, SIG_DFL)
  signal(SIGTTOU, SIG_DFL)

proc forkPipeline(pipeline: Pipeline): seq[Pid] =
  ## Uruchamia potok poleceń zewnętrznych łącząc je przez pipe()+fork(),
  ## zwracając PID-y wszystkich stopni potoku (bez czekania na nie —
  ## czekanie to odpowiedzialność wywołującego, w trybie fg albo bg).
  ## Wszystkie procesy potoku trafiają do JEDNEJ grupy procesów (pgid =
  ## PID pierwszego z nich) — to na niej operuje `tcsetpgrp` przy oddawaniu
  ## terminala (patrz jobcontrol.giveTerminalTo), i to ona jest jednostką
  ## `waitpid`/kontroli zadań (`jobs`/`fg`).
  result = @[]
  var prevReadEnd: cint = -1
  var pgid: Pid = 0

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
      # Ustaw grupę procesów TAKŻE w dziecku (nie tylko w rodzicu poniżej)
      # -- klasyczny wyścig z podręcznika GNU libc: nie wiadomo, które z
      # dwóch (rodzic czy dziecko) wykona się pierwsze, więc oba muszą
      # wywołać setpgid z tym samym wynikiem, żeby uniknąć okna czasowego,
      # w którym proces nie należy jeszcze do żadnej grupy.
      let childPgid = if pgid == 0: 0.Pid else: pgid
      discard setpgid(0, childPgid)
      resetChildSignals()

      if prevReadEnd != -1:
        discard dup2(prevReadEnd, STDIN_FILENO)
        discard close(prevReadEnd)
      if hasNext:
        discard close(pfd[0])
        discard dup2(pfd[1], STDOUT_FILENO)
        discard close(pfd[1])
      execCommand(cmd)
      # execCommand nie wraca.

    if pgid == 0:
      pgid = pid
    discard setpgid(pid, pgid)

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
  let pgid = pids[0]

  if stmt.background:
    discard addJob(pids, pipelineToString(pipeline))
    return 0

  # Czekamy na wszystkie stopnie potoku; kod wyjścia całego potoku to kod
  # OSTATNIEGO polecenia (zgodnie z konwencją powłok uniksowych). Terminal
  # należy do TEJ grupy procesów przez cały czas jej działania (Ctrl+C
  # trafia do niej, nie do zesh) i wraca do zesh dopiero po jej zakończeniu.
  giveTerminalTo(pgid)
  var finalStatus = 0
  var stoppedByTty = false
  for i, pid in pids:
    var status: cint
    # WUNTRACED: bez tej flagi waitpid() NIE zwraca się, gdy proces zostaje
    # zatrzymany (np. Ctrl+Z -> SIGTSTP) -- czekałby w nieskończoność na
    # jego "zakończenie", które nigdy by nie nastąpiło, zamiast oddać
    # kontrolę z powrotem do zesh (jak robi to każda prawdziwa powłoka).
    discard waitpid(pid, status, WUNTRACED)
    if WIFSTOPPED(status):
      # Ctrl+Z: proces WCIĄŻ ISTNIEJE (tylko zatrzymany), więc NIE jest
      # jeszcze reaped -- pozostałe stopnie potoku (jeśli są) dostają
      # analogicznie szansę zgłoszenia własnego zatrzymania/zakończenia
      # w kolejnych iteracjach tej pętli.
      stoppedByTty = true
      finalStatus = 128 + WSTOPSIG(status)
    elif i == pids.len - 1:
      if WIFEXITED(status):
        finalStatus = WEXITSTATUS(status)
      elif WIFSIGNALED(status):
        # Konwencja powłok uniksowych: proces zakończony sygnałem N ma
        # kod wyjścia 128+N (np. 130 dla SIGINT=2, 137 dla SIGKILL=9) --
        # bez tego `$?` po Ctrl+C w pierwszoplanowym poleceniu myląco
        # pokazywał 0 (wartość początkowa), zamiast odzwierciedlać, że
        # proces w ogóle nie zakończył się normalnie.
        finalStatus = 128 + WTERMSIG(status)
  reclaimTerminal()

  if stoppedByTty:
    # Zadanie zatrzymane przez Ctrl+Z NIE zniknęło -- staje się nowym
    # zadaniem w tle (dokładnie jak w bashu), które można wznowić przez
    # `fg %N` albo `bg %N`.
    discard stopJob(pids, pipelineToString(pipeline))

  finalStatus
