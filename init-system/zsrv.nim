import std/[os, posix, tables, strutils, sequtils, times]

const
  Version        = "0.2.0"
  ServiceDir     = "/etc/zenit/services"
  ServiceExt     = ".zsrv"
  LogPath        = "/var/log/zsrv.log"

type
  RestartPolicy = enum
    rpNever, rpAlways, rpOnFailure

  ServiceState = enum
    ssStopped, ssStarting, ssRunning, ssFailed, ssStopping

  ServiceDef = object
    name:        string
    execStart:   string
    after:       seq[string]        # nazwy usług, które muszą wystartować wcześniej
    restart:     RestartPolicy
    restartSec:  int

  ServiceRuntime = object
    def:          ServiceDef
    state:        ServiceState
    pid:          Pid
    lastStart:    Time
    restartCount: int

var
  services: Table[string, ServiceRuntime] = initTable[string, ServiceRuntime]()
  shuttingDown = false

# --------------------------------------------------------------------------
# Logowanie
# --------------------------------------------------------------------------

proc log(msg: string) =
  let line = "[" & $now() & "] " & msg
  echo line
  # TODO: docelowo strukturalny log binarny (jak systemd-journald),
  # na razie prosty dopisek do pliku tekstowego.
  try:
    let f = open(LogPath, fmAppend)
    defer: f.close()
    f.writeLine(line)
  except IOError:
    discard # /var/log może nie być jeszcze zamontowane na wczesnym etapie

# --------------------------------------------------------------------------
# Parsowanie definicji usług
# --------------------------------------------------------------------------

proc parseRestartPolicy(s: string): RestartPolicy =
  case s.strip().toLowerAscii()
  of "always": rpAlways
  of "on-failure": rpOnFailure
  else: rpNever

proc parseServiceFile(path: string): ServiceDef =
  ## Prosty format klucz=wartość, jedna dyrektywa na linię, np.:
  ##
  ##   Name=network
  ##   ExecStart=/usr/lib/zenit/net-up
  ##   After=udev
  ##   Restart=on-failure
  ##   RestartSec=2
  ##
  ## TODO: sekcje w stylu systemd ([Unit]/[Service]), komentarze, cudzysłowy
  ## z argumentami zawierającymi spacje.
  result = ServiceDef(
    name: splitFile(path).name,
    execStart: "",
    after: @[],
    restart: rpNever,
    restartSec: 1,
  )

  for line in lines(path):
    let l = line.strip()
    if l.len == 0 or l.startsWith('#'):
      continue
    let parts = l.split('=', 1)
    if parts.len != 2:
      continue
    let key = parts[0].strip()
    let value = parts[1].strip()
    case key
    of "Name": result.name = value
    of "ExecStart": result.execStart = value
    of "After": result.after = value.split(',').mapIt(it.strip())
    of "Restart": result.restart = parseRestartPolicy(value)
    of "RestartSec": result.restartSec = parseInt(value)
    else:
      log("zsrv: nieznana dyrektywa '" & key & "' w " & path)

proc loadServices(dir: string) =
  if not dirExists(dir):
    log("zsrv: katalog usług '" & dir & "' nie istnieje — pomijam")
    return

  for kind, path in walkDir(dir):
    if kind == pcFile and path.endsWith(ServiceExt):
      try:
        let def = parseServiceFile(path)
        services[def.name] = ServiceRuntime(
          def: def,
          state: ssStopped,
          pid: 0.Pid,
          lastStart: fromUnix(0),
          restartCount: 0,
        )
        log("zsrv: wczytano definicję usługi '" & def.name & "'")
      except CatchableError as e:
        log("zsrv: błąd parsowania '" & path & "': " & e.msg)

# --------------------------------------------------------------------------
# Uruchamianie i nadzorowanie usług
# --------------------------------------------------------------------------

proc dependenciesSatisfied(svc: ServiceRuntime): bool =
  for dep in svc.def.after:
    if dep notin services:
      continue # brakująca zależność — TODO: traktować jako błąd twardy?
    if services[dep].state != ssRunning:
      return false
  true

proc startService(name: string) =
  if name notin services:
    log("zsrv: próba uruchomienia nieznanej usługi '" & name & "'")
    return

  var svc = services[name]
  if svc.state in {ssRunning, ssStarting}:
    return

  if not dependenciesSatisfied(svc):
    # TODO: kolejkowanie i ponowna próba po starcie zależności zamiast
    # cichego pominięcia
    return

  if svc.def.execStart.len == 0:
    log("zsrv: usługa '" & name & "' nie ma ExecStart — pomijam")
    return

  svc.state = ssStarting
  services[name] = svc

  let pid = fork()
  if pid < 0:
    log("zsrv: fork() nie powiódł się dla usługi '" & name & "'")
    svc.state = ssFailed
    services[name] = svc
    return

  if pid == 0:
    # Proces potomny: przygotuj środowisko i wykonaj docelowy program.
    # TODO: ustawienie własnej grupy procesów (setsid), przekierowanie
    # stdout/stderr do logu usługi, obniżenie uprawnień jeśli zdefiniowano
    # User=/Group= w pliku usługi, cgroups.
    let parts = svc.def.execStart.splitWhitespace()
    if parts.len == 0:
      quit(1)
    let cArgs = allocCStringArray(parts)
    discard execvp(parts[0].cstring, cArgs)
    # Jeśli execvp wróciło, to się nie powiodło.
    quit(127)
  else:
    svc.pid = pid
    svc.state = ssRunning
    svc.lastStart = getTime()
    services[name] = svc
    log("zsrv: uruchomiono usługę '" & name & "' (pid=" & $pid & ")")

proc startAllServices() =
  # TODO: właściwe sortowanie topologiczne wg `after` zamiast wielu przebiegów.
  for pass in 0 ..< 5:
    for name in toSeq(services.keys):
      if services[name].state == ssStopped:
        startService(name)

proc handleExitedChild(pid: Pid, exitedOk: bool) =
  for name, svc in services.mpairs:
    if svc.pid == pid:
      log("zsrv: usługa '" & name & "' zakończyła działanie (pid=" & $pid & ", ok=" & $exitedOk & ")")
      svc.pid = 0.Pid

      case svc.def.restart
      of rpAlways:
        svc.state = ssStopped
        svc.restartCount.inc
        # TODO: rzeczywiste opóźnienie restartSec (obecnie natychmiastowy restart)
        startService(name)
      of rpOnFailure:
        if not exitedOk:
          svc.state = ssStopped
          svc.restartCount.inc
          startService(name)
        else:
          svc.state = ssStopped
      of rpNever:
        svc.state = if exitedOk: ssStopped else: ssFailed

      services[name] = svc
      return

proc reapChildren() =
  ## Zbiera wszystkie zakończone procesy potomne (włącznie z osieroconymi
  ## procesami przejętymi przez PID 1), zapobiegając powstawaniu zombie.
  while true:
    var status: cint
    let pid = waitpid(-1.Pid, status, WNOHANG)
    if pid <= 0:
      break
    let exitedOk = WIFEXITED(status) and WEXITSTATUS(status) == 0
    handleExitedChild(pid, exitedOk)

# --------------------------------------------------------------------------
# Obsługa sygnałów
# --------------------------------------------------------------------------

proc onSigchld(sig: cint) {.noconv.} =
  reapChildren()

proc onShutdownSignal(sig: cint) {.noconv.} =
  shuttingDown = true

proc installSignalHandlers() =
  signal(SIGCHLD, onSigchld)
  signal(SIGTERM, onShutdownSignal)
  signal(SIGINT, onShutdownSignal)
  # TODO: SIGHUP -> przeładowanie konfiguracji (ponowne wczytanie ServiceDir)

proc stopAllServices() =
  log("zsrv: zatrzymywanie wszystkich usług...")
  for name, svc in services:
    if svc.state == ssRunning and svc.pid != 0.Pid:
      discard kill(svc.pid, SIGTERM)
  # TODO: odczekać na zakończenie (z limitem czasu) przed SIGKILL

# --------------------------------------------------------------------------
# Główna pętla
# --------------------------------------------------------------------------

proc mainLoop() =
  while not shuttingDown:
    # Nadzorca działa głównie reaktywnie (przez sygnały), ale okresowo
    # sprawdzamy też, czy pojawiły się usługi gotowe do wystartowania
    # (np. po spełnieniu zależności).
    startAllServices()
    sleep(1000)
    # TODO: zamiast pollingu co 1s, użyć epoll/select na deskryptorze
    # sygnałowym (signalfd) dla czystszej pętli zdarzeń.

  stopAllServices()
  log("zsrv: zamykanie systemu zakończone")

when isMainModule:
  if paramCount() >= 1 and paramStr(1) in ["-v", "--version"]:
    echo "zsrv " & Version
    quit(0)

  if getpid().int != 1:
    stderr.writeLine("zsrv: ostrzeżenie — proces nie jest PID 1 (tryb testowy?)")
    # W trybie deweloperskim pozwalamy uruchomić się jako zwykły proces,
    # aby móc testować logikę bez faktycznego bycia init systemem.

  log("zsrv " & Version & " — uruchamianie...")
  installSignalHandlers()
  loadServices(ServiceDir)
  startAllServices()
  mainLoop()
