import std/[tables, posix, terminal]

type
  JobState* = enum
    jsRunning, jsStopped, jsDone

  Job* = object
    id*:      int
    pgid*:    Pid
    pids*:    seq[Pid]
    command*: string
    state*:   JobState

var
  jobs*:   Table[int, Job] = initTable[int, Job]()
  nextJobId = 1

  shellTerminal*: cint = STDIN_FILENO
  shellIsInteractive*: bool = false
  shellPgid*: Pid = 0
    ## Grupa procesów samej powłoki. Terminal jest oddawany grupie procesów
    ## PIERWSZOPLANOWEGO zadania na czas jego działania (patrz
    ## `giveTerminalTo`/`reclaimTerminal` niżej) i odbierany z powrotem tej
    ## grupie, gdy zadanie kończy pracę — to jest rzeczywiste oddanie
    ## terminala procesowi (poprzednio: TODO).

proc initJobControl*() =
  ## Standardowa sekwencja inicjalizacji interaktywnej powłoki z kontrolą
  ## zadań (patrz GNU libc manual, rozdz. "Implementing a Job Control
  ## Shell"): upewnij się, że zesh jest liderem WŁASNEJ grupy procesów i
  ## posiada terminal, oraz zignoruj sygnały związane z kontrolą zadań,
  ## które w przeciwnym razie mogłyby zatrzymać/przerwać samą powłokę
  ## (np. SIGTTOU przy wywołaniu tcsetpgrp, gdyby zesh nie było jeszcze
  ## grupą pierwszoplanową). Wywoływane raz, na starcie zesh.nim.
  shellIsInteractive = isatty(shellTerminal) != 0
  if not shellIsInteractive:
    return

  # Jeśli zesh zostało uruchomione w tle (np. `zesh &` z innej powłoki),
  # czekaj aż stanie się pierwszoplanowe, zanim przejmie terminal --
  # inaczej sama wysyłka SIGTTIN do siebie (zignorowanego dopiero PO tej
  # pętli) by je zatrzymała w nieskończoność. To standardowy idiom z
  # cytowanego wyżej podręcznika GNU libc.
  while tcgetpgrp(shellTerminal) != getpgrp():
    discard posix.kill(-getpgrp(), SIGTTIN)

  signal(SIGINT, SIG_IGN)
  signal(SIGQUIT, SIG_IGN)
  signal(SIGTSTP, SIG_IGN)
  signal(SIGTTIN, SIG_IGN)
  signal(SIGTTOU, SIG_IGN)

  shellPgid = getpid()
  if getpgrp() != shellPgid:
    # Liderzy sesji (np. zesh uruchomione bezpośrednio na świeżym pty, co
    # samo w sobie czyni je liderem sesji I już własnej grupy procesów)
    # NIE MOGĄ wywołać na sobie setpgid — jądro zwraca EPERM niezależnie
    # od tego, czy docelowe pgid jest inne, czy identyczne z obecnym.
    # Stąd wywołujemy setpgid TYLKO, gdy faktycznie trzeba coś zmienić.
    if setpgid(shellPgid, shellPgid) < 0:
      stderr.styledWriteLine(fgRed, "zesh: nie udalo sie ustawic grupy procesow powloki -- kontrola terminala wylaczona")
      shellIsInteractive = false
      return

  discard tcsetpgrp(shellTerminal, shellPgid)

proc giveTerminalTo*(pgid: Pid) =
  ## Oddaje terminal grupie procesów `pgid` (zadanie pierwszoplanowe) --
  ## dzięki temu np. Ctrl+C trafia do TEGO zadania, nie do zesh.
  if shellIsInteractive and pgid > 0:
    discard tcsetpgrp(shellTerminal, pgid)

proc reclaimTerminal*() =
  ## Odbiera terminal z powrotem powłoce -- wywoływane, gdy zadanie
  ## pierwszoplanowe kończy pracę (albo zostaje przeniesione w tło).
  if shellIsInteractive:
    discard tcsetpgrp(shellTerminal, shellPgid)

proc registerJob*(pids: seq[Pid], command: string, state: JobState): int =
  ## Rejestruje nowe zadanie (w dowolnym stanie startowym) i zwraca jego
  ## numer -- wspólny mechanizm dla `addJob` (start w tle przez `&`) i
  ## `stopJob` (zatrzymanie pierwszoplanowego zadania przez Ctrl+Z).
  let id = nextJobId
  inc nextJobId
  let pgid = if pids.len > 0: pids[0] else: Pid(0)
  jobs[id] = Job(id: id, pgid: pgid, pids: pids, command: command, state: state)
  id

proc addJob*(pids: seq[Pid], command: string): int =
  let id = registerJob(pids, command, jsRunning)
  echo "[" & $id & "] " & $pids[^1]
  id

proc stopJob*(pids: seq[Pid], command: string): int =
  ## Rejestruje jako NOWE zadanie w tle polecenie pierwszoplanowe, które
  ## właśnie zostało zatrzymane przez Ctrl+Z (SIGTSTP) -- dokładnie tak,
  ## jak robi to bash: zadanie zatrzymane dostaje numer zadania i można
  ## je wznowić przez `fg`/`bg`.
  let id = registerJob(pids, command, jsStopped)
  stdout.styledWriteLine(fgYellow, "[" & $id & "]+  Zatrzymano (Ctrl+Z)", fgDefault, "\t" & command)
  id

proc continueJobBg*(id: int): bool =
  ## `bg %N`: wysyła SIGCONT do całej grupy procesów zatrzymanego zadania
  ## i oznacza je jako działające w tle -- BEZ oddawania mu terminala
  ## (w przeciwieństwie do `fg`), więc zesh od razu wraca do promptu.
  if id notin jobs:
    stderr.writeLine("zesh: bg: brak zadania %" & $id)
    return false

  var job = jobs[id]
  if job.state == jsDone:
    stderr.writeLine("zesh: bg: zadanie %" & $id & " juz zakonczone")
    return false
  if job.state == jsRunning:
    stderr.writeLine("zesh: bg: zadanie %" & $id & " juz dziala")
    return false

  discard posix.kill(-job.pgid, SIGCONT)
  job.state = jsRunning
  jobs[id] = job
  echo "[" & $id & "]+ " & job.command & " &"
  true

proc refreshJobStatuses*() =
  ## Sprawdza (nieblokująco) czy któreś z zadań w tle się zakończyło albo
  ## zostało zatrzymane, i informuje o tym użytkownika -- wywoływane przed
  ## każdym nowym promptem. `WUNTRACED` wykrywa też zadania w tle, które same
  ## się zatrzymały (np. próba odczytu z terminala -> SIGTTIN nieignorowane
  ## w procesie potomnym, patrz exec.resetChildSignals).
  for id, job in jobs.mpairs:
    if job.state == jsDone: continue

    var allDone = true
    var anyStopped = false
    for pid in job.pids:
      var status: cint
      let r = waitpid(pid, status, WNOHANG or WUNTRACED)
      if r == 0:
        allDone = false # ten proces w potoku wciąż działa
      elif r > 0 and WIFSTOPPED(status):
        allDone = false
        anyStopped = true

    if anyStopped:
      if job.state != jsStopped:
        job.state = jsStopped
        stdout.styledWriteLine(fgYellow, "[" & $id & "]+  Zatrzymano", fgDefault, "    " & job.command)
    elif allDone:
      job.state = jsDone
      stdout.styledWriteLine(fgGreen, "[" & $id & "]+  Done", fgDefault, "    " & job.command)

proc listJobs*() =
  for id, job in jobs:
    let marker =
      case job.state
      of jsRunning: "Running"
      of jsStopped: "Stopped"
      of jsDone: "Done"
    echo "[" & $id & "]  " & marker & "\t" & job.command

proc waitForJob*(id: int) =
  ## `fg %N`: jeśli zadanie było zatrzymane, wznawia je (SIGCONT), oddaje
  ## terminal jego grupie procesów i czeka blokująco aż WSZYSTKIE procesy
  ## w nim się zakończą ALBO zadanie zostanie ponownie zatrzymane (kolejny
  ## Ctrl+Z) -- w tym drugim przypadku terminal wraca do zesh, a zadanie
  ## zostaje ponownie oznaczone jako zatrzymane, zamiast usunięte z listy.
  if id notin jobs:
    stderr.writeLine("zesh: fg: brak zadania %" & $id)
    return

  var job = jobs[id]
  if job.state == jsStopped:
    discard posix.kill(-job.pgid, SIGCONT)
  echo job.command

  giveTerminalTo(job.pgid)
  var stoppedAgain = false
  for pid in job.pids:
    var status: cint
    discard waitpid(pid, status, WUNTRACED)
    if WIFSTOPPED(status):
      stoppedAgain = true
  reclaimTerminal()

  if stoppedAgain:
    job.state = jsStopped
    jobs[id] = job
    stdout.styledWriteLine(fgYellow, "[" & $id & "]+  Zatrzymano", fgDefault, "\t" & job.command)
  else:
    job.state = jsDone
    jobs[id] = job
