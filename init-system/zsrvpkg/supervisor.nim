import std/[os, posix, strutils, sequtils, times]
import ./types
import ./state
import ./log
import ./cgroups
import ./depgraph

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
    # Proces potomny: przypisz do cgroupy, obniż uprawnienia (jeśli User=),
    # przygotuj argumenty i wykonaj docelowy program.
    attachPidToCgroup(name, getpid().int32)
    if svc.def.user.len > 0:
      dropPrivileges(svc.def.user)

    # TODO: setsid() do własnej grupy procesów oraz przekierowanie
    # stdout/stderr do /var/log/zenit/<usługa>.log zamiast dziedziczenia
    # deskryptorów PID 1.
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
  ## należące do danego targetu, które nie są jeszcze uruchomione.
  ## TODO: zatrzymywanie usług NIE należących do nowego targetu przy
  ## przełączaniu (dziś applyTarget tylko dokłada usługi).
  let names = servicesForTarget(target)
  let order = topologicalStartOrder(names)
  for name in order:
    if services[name].state == ssStopped:
      startService(name)

proc handleExitedChild*(pid: int32, exitedOk: bool) =
  for name, svc in services.mpairs:
    if svc.pid == pid:
      logService(name, "zakończyła działanie (pid=" & $pid & ", ok=" & $exitedOk & ")")
      svc.pid = 0

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
        discard kill(svc.pid.Pid, SIGKILL)
      svc.stopDeadline = fromUnix(0)

proc nextWakeupDeadline*(): int =
  ## Zwraca liczbę milisekund do najbliższego zdarzenia czasowego (restart
  ## usługi albo eskalacja SIGKILL), albo -1, jeśli nic nie jest zaplanowane.
  ## Używane jako timeout dla epoll_wait w pętli zdarzeń.
  var earliest: Time
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

proc stopAllServices*() =
  ## Faza 1 zamykania: wysyła SIGTERM do wszystkich działających usług i
  ## planuje SIGKILL po upływie StopSec= dla każdej z nich (obsługiwane
  ## później przez processStopEscalations w pętli zdarzeń).
  log("zsrv: zatrzymywanie wszystkich usług...")
  for name, svc in services.mpairs:
    if svc.state == ssRunning and svc.pid != 0:
      discard kill(svc.pid.Pid, SIGTERM)
      svc.state = ssStopping
      svc.stopDeadline = getTime() + initDuration(seconds = svc.def.stopSec)
