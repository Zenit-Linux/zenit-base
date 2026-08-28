import std/[posix, os, times]
import ./types
import ./state
import ./logger
import ./supervisor
import ./target
import ./parser

# --------------------------------------------------------------------------
# Bindingi niskiego poziomu: epoll + signalfd (Linux).
#
# Własne, minimalne deklaracje `importc` zamiast polegania na dokładnym
# kształcie `std/posix` na danej wersji Nim — te API są stabilną częścią
# ABI Linuksa (glibc).
# --------------------------------------------------------------------------

const
  EPOLL_CTL_ADD = 1'i32
  EPOLLIN       = 0x001'u32
  SFD_NONBLOCK  = 0o4000'i32

type
  EpollDataUnion {.union.} = object
    dataPtr: pointer
    fd:      cint
    u32:     uint32
    u64:     uint64

  EpollEvent {.importc: "struct epoll_event", header: "<sys/epoll.h>", pure, final.} = object
    events: uint32
    data:   EpollDataUnion

  SignalfdSiginfo {.importc: "struct signalfd_siginfo", header: "<sys/signalfd.h>", pure, final.} = object
    ssiSigno: uint32
    padding: array[124, uint8] # dopełnienie do pełnego rozmiaru struktury (128 B)

proc epoll_create1(flags: cint): cint {.importc, header: "<sys/epoll.h>".}
proc epoll_ctl(epfd: cint, op: cint, fd: cint, event: ptr EpollEvent): cint {.importc, header: "<sys/epoll.h>".}
proc epoll_wait(epfd: cint, events: ptr EpollEvent, maxevents: cint, timeout: cint): cint {.importc, header: "<sys/epoll.h>".}
proc signalfd(fd: cint, mask: ptr Sigset, flags: cint): cint {.importc, header: "<sys/signalfd.h>".}

proc setupSignalFd(): cint =
  var mask: Sigset
  discard sigemptyset(mask)
  discard sigaddset(mask, SIGCHLD)
  discard sigaddset(mask, SIGTERM)
  discard sigaddset(mask, SIGINT)
  discard sigaddset(mask, SIGHUP)

  # Blokujemy te sygnały w standardowym mechanizmie — będą odbierane
  # wyłącznie przez odczyt z signalfd w pętli zdarzeń.
  discard sigprocmask(SIG_BLOCK, mask, nil)

  let fd = signalfd(-1.cint, addr mask, SFD_NONBLOCK)
  if fd < 0:
    log("zsrv: signalfd() nie powiodlo sie — ograniczona obsluga sygnalow")
  fd

proc handleSignal(signo: uint32) =
  case signo.cint
  of SIGCHLD:
    reapChildren()
  of SIGTERM, SIGINT:
    log("zsrv: otrzymano sygnal zamkniecia systemu")
    shuttingDown = true
  of SIGHUP:
    log("zsrv: SIGHUP — przeladowanie konfiguracji uslug")
    loadServices(ServiceDir)

    let newTarget = readRuntimeTargetOverride()
    if newTarget != currentTarget:
      log("zsrv: przelaczanie targetu '" & $currentTarget & "' -> '" & $newTarget & "'")
      currentTarget = newTarget

    applyTarget(currentTarget)
  else:
    discard

proc mainLoop*() =
  let sfd = setupSignalFd()
  let epfd = epoll_create1(0)

  if sfd >= 0 and epfd >= 0:
    var ev = EpollEvent(events: EPOLLIN)
    ev.data.fd = sfd
    discard epoll_ctl(epfd, EPOLL_CTL_ADD, sfd, addr ev)

  applyTarget(currentTarget)

  while not shuttingDown:
    if epfd < 0 or sfd < 0:
      # Brak signalfd/epoll (np. platforma niewspierana) — awaryjnie
      # wracamy do prostego pollingu, żeby zsrv wciąż działał.
      reapChildren()
      processPendingRestarts()
      processStopEscalations()
      applyTarget(currentTarget)
      sleep(200)
      continue

    var events: array[4, EpollEvent]
    let timeoutMs = nextWakeupDeadline()
    let n = epoll_wait(epfd, addr events[0], events.len.cint, timeoutMs.cint)

    if n > 0:
      for i in 0 ..< n:
        if events[i].data.fd == sfd:
          var info: SignalfdSiginfo
          let bytesRead = read(sfd, addr info, sizeof(SignalfdSiginfo))
          if bytesRead == sizeof(SignalfdSiginfo):
            handleSignal(info.ssiSigno)

    processPendingRestarts()
    processStopEscalations()
    applyTarget(currentTarget) # dokłada usługi, których zależności właśnie się spełniły

  stopAllServices()

  # Faza 2 zamykania: czekamy (z limitem czasu) na zakończenie usług objętych
  # eskalacją SIGTERM -> SIGKILL zaplanowaną przez stopAllServices(), zamiast
  # kończyć proces PID 1 natychmiast i zostawiać osierocone procesy potomne.
  let shutdownStart = epochTime()
  while epochTime() - shutdownStart < 15.0:
    reapChildren()
    processStopEscalations()
    var anyRunning = false
    for svc in services.values:
      if svc.state == ssStopping:
        anyRunning = true
    if not anyRunning:
      break
    sleep(100)

  log("zsrv: zamykanie systemu zakończone")
