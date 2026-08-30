import std/[os, posix, strutils, sequtils, times, tables]
import ./types
import ./state
import ./logger
import ./cgroups
import ./depgraph

const ServiceLogDir = "/var/log/zenit"

proc dependenciesSatisfied(svc: ServiceRuntime): bool =
  for dep in svc.def.after:
    if dep notin services:
      continue # brakująca zależność — TODO: traktować jako błąd twardy?
    if services[dep].state != ssRunning:
      return false
  true

proc dropPrivileges(username: string) =
  ## Wywoływane W PROCESIE POTOMNYM, po fork(), przed execvp(), gdy usługa
  ## zdefiniowała User=. Kolejność setgid PRZED setuid jest kluczowa —
  ## po obniżeniu uid nie mielibyśmy już uprawnień do zmiany gid.
  let pw = getpwnam(username.cstring)
  if pw == nil:
    stderr.writeLine("zsrv: nieznany użytkownik '" & username & "' — pozostaję jako root")
    return

  if setgid(pw.pw_gid) != 0:
    stderr.writeLine("zsrv: setgid() nie powiodlo sie dla '" & username & "'")
  if setuid(pw.pw_uid) != 0:
    stderr.writeLine("zsrv: setuid() nie powiodlo sie dla '" & username & "'")

proc redirectServiceOutput(name: string) =
  ## Wywoływane W PROCESIE POTOMNYM, po fork(), przed execvp(): przepina
  ## stdout/stderr na dedykowany plik logu usługi, zamiast dziedziczenia
  ## deskryptorów PID 1 (co mieszałoby wyjścia wszystkich usług razem).
  try:
    if not dirExists(ServiceLogDir):
      createDir(ServiceLogDir)
  except OSError:
    return # brak /var/log/zenit — usługa i tak wystartuje, tylko bez własnego logu

  let logPath = ServiceLogDir / (name & ".log")
  let fd = posix.open(logPath.cstring, O_WRONLY or O_CREAT or O_APPEND, 0o644)
  if fd >= 0:
    discard dup2(fd, STDOUT_FILENO)
    discard dup2(fd, STDERR_FILENO)
    discard close(fd)

proc stopService*(name: string)
  ## Forward declaration -- `startService` (poniżej) woła `stopService` w
  ## gałęzi restartu (np. usługa typu "oneshot", która już raz
  ## zakończyła działanie i jest uruchamiana ponownie), a `stopService`
  ## jest zdefiniowane dalej w tym samym pliku. Nim wymaga jawnej
  ## deklaracji w przód dla wzajemnie rekurencyjnych/naprzód-
  ## odwołujących się proc na tym samym poziomie modułu -- bez tego
  ## kompilacja `zsrv.nim` kończy się błędem "undeclared identifier:
  ## 'stopService'" dokładnie w miejscu wywołania w linii poniżej.

proc startService*(name: string) =
  if name notin services:
    log("zsrv: próba uruchomienia nieznanej usługi '" & name & "'")
    return

  var svc = services[name]
  if svc.state in {ssRunning, ssStarting}:
    return

  if not dependenciesSatisfied(svc):
    return # zostanie ponowiona w kolejnym przebiegu applyTarget

  if svc.def.execStart.len == 0:
    log("zsrv: usługa '" & name & "' nie ma ExecStart — pomijam")
    return

  createServiceCgroup(name, svc.def.limits)

  svc.state = ssStarting
  services[name] = svc

  let pid = fork()
  if pid < 0:
    log("zsrv: fork() nie powiódł się dla usługi '" & name & "'")
    svc.state = ssFailed
    services[name] = svc
    return

  if pid == 0:
    # Proces potomny: nowa grupa procesów, przypisanie do cgroupy,
    # przekierowanie logów, obniżenie uprawnień (jeśli User=), przygotuj
    # argumenty i wykonaj docelowy program.
    discard setsid() # własne PGID — pozwala potem zabić CAŁĄ grupę (dzieci usługi też)
    attachPidToCgroup(name, getpid().int32)
    redirectServiceOutput(name)
    if svc.def.user.len > 0:
      dropPrivileges(svc.def.user)

    let parts = svc.def.execStart.splitWhitespace()
    if parts.len == 0:
      quit(1)
    let cArgs = allocCStringArray(parts)
    discard execvp(parts[0].cstring, cArgs)
    quit(127) # execvp wróciło => się nie powiodło

  svc.pid = pid.int32
  svc.state = ssRunning
  svc.lastStart = getTime()
  services[name] = svc
  logService(name, "uruchomiono (pid=" & $pid & ")")

proc servicesForTarget*(target: Target): seq[string] =
  toSeq(services.keys).filterIt(target in services[it].def.wantedBy)

proc applyTarget*(target: Target) =
  ## Uruchamia (w poprawnej kolejności zależności) wszystkie usługi
  ## należące do danego targetu, które nie są jeszcze uruchomione, ORAZ
  ## zatrzymuje usługi DZIAŁAJĄCE, które nie należą do aktywnego targetu
  ## (np. usługi tylko-multi-user po przełączeniu na rescue).
  let names = servicesForTarget(target)
  let order = topologicalStartOrder(names)
  for name in order:
    if services[name].state == ssStopped:
      startService(name)

  for name in toSeq(services.keys):
    if target notin services[name].def.wantedBy and services[name].state == ssRunning:
      stopService(name)

proc handleExitedChild*(pid: int32, exitedOk: bool) =
  for name, svc in services.mpairs:
    if svc.pid == pid:
      logService(name, "zakończyła działanie (pid=" & $pid & ", ok=" & $exitedOk & ")")
      svc.pid = 0
      removeCgroup(name) # bezpieczne również gdy usługa zaraz wystartuje ponownie

      case svc.def.restart
      of rpAlways:
        svc.state = ssStopped
        svc.restartCount.inc
        svc.restartAt = getTime() + initDuration(seconds = svc.def.restartSec)
      of rpOnFailure:
        if not exitedOk:
          svc.state = ssStopped
          svc.restartCount.inc
          svc.restartAt = getTime() + initDuration(seconds = svc.def.restartSec)
        else:
          svc.state = ssStopped
      of rpNever:
        svc.state = if exitedOk: ssStopped else: ssFailed

      return

proc processPendingRestarts*() =
  ## Uruchamia ponownie usługi, których `restartAt` już minął.
  let now = getTime()
  for name in toSeq(services.keys):
    let svc = services[name]
    if svc.state == ssStopped and svc.restartAt > fromUnix(0) and svc.restartAt <= now:
      var s = svc
      s.restartAt = fromUnix(0)
      services[name] = s
      startService(name)

proc processStopEscalations*() =
  ## Dla usług w stanie ssStopping, którym minął `stopDeadline` (StopSec=
  ## sekund od wysłania SIGTERM), wysyła SIGKILL.
  let now = getTime()
  for name, svc in services.mpairs:
    if svc.state == ssStopping and svc.stopDeadline > fromUnix(0) and svc.stopDeadline <= now:
      if svc.pid != 0:
        logService(name, "nie zareagowała na SIGTERM w porę — wysyłam SIGKILL")
        discard kill((-svc.pid).Pid, SIGKILL) # PID ujemny = cała grupa procesów (setsid() w startService)
      svc.stopDeadline = fromUnix(0)

proc nextWakeupDeadline*(): int =
  ## Zwraca liczbę milisekund do najbliższego zdarzenia czasowego (restart
  ## usługi albo eskalacja SIGKILL), albo -1, jeśli nic nie jest zaplanowane.
  ## Używane jako timeout dla epoll_wait w pętli zdarzeń.
  var earliest: times.Time
  var found = false
  let now = getTime()

  for svc in services.values:
    if svc.restartAt > fromUnix(0):
      if not found or svc.restartAt < earliest:
        earliest = svc.restartAt
        found = true
    if svc.stopDeadline > fromUnix(0):
      if not found or svc.stopDeadline < earliest:
        earliest = svc.stopDeadline
        found = true

  if not found:
    return -1
  let diffMs = int((earliest - now).inMilliseconds)
  max(diffMs, 0)

proc reapChildren*() =
  ## Zbiera wszystkie zakończone procesy potomne (włącznie z osieroconymi
  ## procesami przejętymi przez PID 1), zapobiegając powstawaniu zombie.
  while true:
    var status: cint
    let pid = waitpid(-1.Pid, status, WNOHANG)
    if pid <= 0:
      break
    let exitedOk = WIFEXITED(status) and WEXITSTATUS(status) == 0
    handleExitedChild(pid.int32, exitedOk)

proc stopService*(name: string) =
  ## Zatrzymuje POJEDYNCZĄ usługę: SIGTERM do całej grupy procesów i
  ## zaplanowanie SIGKILL po StopSec= sekundach (eskalacja obsługiwana
  ## przez processStopEscalations w pętli zdarzeń). Używane zarówno przez
  ## stopAllServices (zamykanie systemu), jak i applyTarget (usługa
  ## przestała należeć do aktywnego targetu).
  if name notin services:
    return
  var svc = services[name]
  if svc.state != ssRunning or svc.pid == 0:
    return

  discard kill((-svc.pid).Pid, SIGTERM) # PID ujemny = cała grupa procesów (setsid() w startService)
  svc.state = ssStopping
  svc.stopDeadline = getTime() + initDuration(seconds = svc.def.stopSec)
  services[name] = svc

proc stopAllServices*() =
  ## Faza 1 zamykania: wysyła SIGTERM do wszystkich działających usług i
  ## planuje SIGKILL po upływie StopSec= dla każdej z nich (obsługiwane
  ## później przez processStopEscalations w pętli zdarzeń).
  log("zsrv: zatrzymywanie wszystkich usług...")
  for name in toSeq(services.keys):
    stopService(name)
