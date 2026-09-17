import std/[os, strutils, tables]
import ./types
import ./state
import ./logger
import ./supervisor
import ./target
import ./parser

## Gniazdo kontrolne zsrv (`/run/zenit/control.sock`, AF_UNIX/SOCK_STREAM).
##
## Zastępuje ręczny protokół "echo target > plik && kill -HUP 1" wygodnym,
## tekstowym API dla narzędzia `zsrvctl` (tools/zsrvctl w Crystalu) i dla
## innych ewentualnych klientów: jedna linia poleceń wejściowych, jedna (lub
## więcej) linia odpowiedzi tekstowej, zakończone zamknięciem połączenia
## przez zsrv.
##
## Tak jak w zsrvpkg/eventloop (epoll/signalfd), API gniazd deklarujemy
## SAMI jako minimalne `importc` zamiast polegać na dokładnym kształcie
## `std/posix` (gdzie `SocketHandle` jest typem `distinct`, co w praktyce
## tylko komplikuje mieszanie z resztą kodu operującego na zwykłych
## deskryptorach `cint`) — te wywołania są stabilną częścią ABI Linuksa/glibc.
##
## Obsługiwane polecenia (wielkość liter w nazwie polecenia bez znaczenia):
##   list                    -> jedna linia na usługę: "nazwa stan pid restartCount"
##   status <nazwa>          -> szczegóły jednej usługi albo "ERR nieznana usluga"
##   start <nazwa>           -> uruchamia usługę natychmiast
##   stop <nazwa>            -> zatrzymuje usługę (dwufazowo, jak przy zamykaniu)
##   restart <nazwa>         -> stop + start
##   isolate <target>        -> przełącza target w locie (jak SIGHUP + /run/zenit/target)
##   reload                  -> ponowne wczytanie plików .zsrv z zachowaniem stanu (patrz zsrvpkg/parser.reloadServices)
##   logs <nazwa> [N]        -> ostatnie N linii logu usługi (domyślnie 20, maks. 500)
##   ping                    -> "OK pong" (test żywotności)
## Każda odpowiedź kończy się linią "OK" albo "ERR <opis>".

const
  SocketPath = "/run/zenit/control.sock"
  AF_UNIX = 1'i32
  SOCK_STREAM = 1'i32
  SUN_PATH_LEN = 108

type
  CSockaddrUn {.importc: "struct sockaddr_un", header: "<sys/un.h>", pure, final.} = object
    sunFamily {.importc: "sun_family".}: cushort
    sunPath {.importc: "sun_path".}: array[SUN_PATH_LEN, char]

proc c_socket(domain, typ, protocol: cint): cint {.importc: "socket", header: "<sys/socket.h>".}
proc c_bind(sockfd: cint, address: ptr CSockaddrUn, addrlen: cuint): cint {.importc: "bind", header: "<sys/socket.h>".}
proc c_listen(sockfd: cint, backlog: cint): cint {.importc: "listen", header: "<sys/socket.h>".}
proc c_accept(sockfd: cint, address: pointer, addrlen: pointer): cint {.importc: "accept", header: "<sys/socket.h>".}
proc c_read(fd: cint, buf: pointer, count: csize_t): cint {.importc: "read", header: "<unistd.h>".}
proc c_write(fd: cint, buf: pointer, count: csize_t): cint {.importc: "write", header: "<unistd.h>".}
proc c_close(fd: cint): cint {.importc: "close", header: "<unistd.h>".}
proc c_unlink(path: cstring): cint {.importc: "unlink", header: "<unistd.h>".}
proc c_chmod(path: cstring, mode: cint): cint {.importc: "chmod", header: "<sys/stat.h>".}
proc c_fcntl(fd: cint, cmd: cint, arg: cint): cint {.importc: "fcntl", varargs, header: "<fcntl.h>".}

const
  F_GETFL = 3'i32
  F_SETFL = 4'i32
  O_NONBLOCK = 0o4000'i32
    ## Wartość na Linuksie/x86_64 (potwierdzona empirycznie: bez tego
    ## flaga `acceptControlConnection` blokowała się na DRUGIM wywołaniu
    ## `accept()` w pętli "przyjmij wszystkie oczekujące połączenia" w
    ## zsrvpkg/eventloop, zamrażając CAŁĄ pętlę zdarzeń zsrv na zawsze po
    ## obsłużeniu pierwszego w historii połączenia od zsrvctl — patrz
    ## `setNonBlocking` niżej i notatka przy `acceptControlConnection`).

proc setNonBlocking(fd: cint) =
  let flags = c_fcntl(fd, F_GETFL, 0'i32)
  if flags >= 0:
    discard c_fcntl(fd, F_SETFL, flags or O_NONBLOCK)

var listenFd*: cint = -1

proc closeListener*() =
  if listenFd >= 0:
    discard c_close(listenFd)
    listenFd = -1
  discard c_unlink(SocketPath.cstring)

proc setupControlSocket*(): cint =
  ## Tworzy i binduje gniazdo nasłuchujące w `/run/zenit/`. Best-effort:
  ## brak `/run/zenit` (np. wczesny etap rozruchu bez zamontowanego tmpfs)
  ## albo zajęte gniazdo z poprzedniej, niedoczyszczonej instancji nie są
  ## traktowane jako błąd krytyczny — zsrv działa dalej bez zdalnej
  ## kontroli, polegając wyłącznie na sygnałach jak dotychczas.
  try:
    createDir("/run/zenit")
  except OSError:
    discard

  discard c_unlink(SocketPath.cstring) # sprzątanie po ewentualnej poprzedniej instancji

  let fd = c_socket(AF_UNIX, SOCK_STREAM, 0)
  if fd < 0:
    log("zsrv: nie udalo sie utworzyc gniazda kontrolnego (socket())")
    return -1

  var address: CSockaddrUn
  address.sunFamily = AF_UNIX.cushort
  if SocketPath.len >= SUN_PATH_LEN:
    log("zsrv: sciezka gniazda kontrolnego zbyt dluga: " & SocketPath)
    discard c_close(fd)
    return -1
  for i in 0 ..< SocketPath.len:
    address.sunPath[i] = SocketPath[i]
  address.sunPath[SocketPath.len] = '\0'

  # Rozmiar rzeczywiście używanej ścieżki (offset pola sun_path + długość
  # + terminator), zgodnie z konwencją man 7 unix, zamiast pełnego
  # sizeof(struct sockaddr_un) — obie formy są akceptowane przez Linuksa,
  # ale ta jest bardziej precyzyjna.
  let addrLen = cuint(sizeof(cushort) + SocketPath.len + 1)

  if c_bind(fd, addr address, addrLen) != 0:
    log("zsrv: bind() na " & SocketPath & " nie powiodlo sie")
    discard c_close(fd)
    return -1

  discard c_chmod(SocketPath.cstring, 0o660)

  if c_listen(fd, 8) != 0:
    log("zsrv: listen() na gniezdzie kontrolnym nie powiodlo sie")
    discard c_close(fd)
    return -1

  # KRYTYCZNE: gniazdo nasłuchujące MUSI być nieblokujące. `handleControlConnection`
  # jest wołane z pętli "przyjmij WSZYSTKIE oczekujące połączenia" w
  # zsrvpkg/eventloop (`while true: accept -> break gdy brak kolejnych`) --
  # bez O_NONBLOCK drugie (i każde kolejne) wywołanie `accept()` w tej
  # pętli, gdy nie ma już nic do przyjęcia, BLOKUJE SIĘ w nieskończoność
  # zamiast zwrócić błąd EAGAIN, zamrażając CAŁĄ jednowątkową pętlę
  # zdarzeń zsrv na zawsze po obsłużeniu pierwszego w historii połączenia.
  # (Błąd znaleziony i naprawiony przez rzeczywisty test end-to-end z
  # `zsrvctl` — każde kolejne połączenie po pierwszym wisiało bez końca.)
  setNonBlocking(fd)

  listenFd = fd
  fd

proc acceptControlConnection*(): cint =
  ## `accept()` na gnieździe nasłuchującym; -1 jeśli nic nie czeka (gniazdo
  ## jest nieblokujące -- patrz `setupControlSocket`) albo gniazdo kontrolne
  ## nie zostało uruchomione. Adres klienta (AF_UNIX, zwykle anonimowy po
  ## stronie klienta) nas nie interesuje, stąd `nil`.
  if listenFd < 0:
    return -1
  c_accept(listenFd, nil, nil)

proc closeConnection*(fd: cint) =
  discard c_close(fd)

proc formatState(s: ServiceState): string =
  case s
  of ssStopped:  "stopped"
  of ssStarting: "starting"
  of ssRunning:  "running"
  of ssFailed:   "failed"
  of ssStopping: "stopping"

proc handleIsolate(targetName: string): string =
  let normalized = targetName.strip().toLowerAscii()
  let newTarget =
    case normalized
    of "rescue": tgRescue
    of "multi-user": tgMultiUser
    else: return "ERR nieznany target: '" & targetName & "'"

  if newTarget != currentTarget:
    log("zsrv: zsrvctl isolate -> przelaczanie targetu '" & $currentTarget & "' -> '" & $newTarget & "'")
    currentTarget = newTarget
    applyTarget(currentTarget, force = true)
  else:
    log("zsrv: zsrvctl isolate " & $newTarget & " (juz aktywny)")

  "OK target=" & $newTarget

const
  DefaultLogsRequested = 20
  MaxLogsRequested = 500
  LogTailReadCap = 256'i64 * 1024'i64
    ## Logi usług (w odróżnieniu od /var/log/zsrv.log w zsrvpkg/logger)
    ## nie mają dziś rotacji, więc mogłyby urosnąć dowolnie duże — przy
    ## odczycie ogona czytamy więc tylko ostatnie `LogTailReadCap`
    ## bajtów pliku zamiast całości. Typ `int64`, bo `getFileSize(File)`
    ## zwraca `int64`, a Nim nie konwertuje niejawnie `int64` <-> `int`.

proc tailLines(path: string, n: int): seq[string] =
  ## Zwraca (maksymalnie) `n` ostatnich linii pliku `path`, best-effort:
  ## brak pliku albo błąd otwarcia dają po prostu pustą sekwencję.
  if not fileExists(path):
    return @[]
  var f: File
  if not open(f, path, fmRead):
    return @[]
  defer: f.close()

  let size = getFileSize(f)
  let readFrom: int64 = if size > LogTailReadCap: size - LogTailReadCap else: 0'i64
  f.setFilePos(readFrom)
  let content = f.readAll()
  var lines = content.splitLines()

  if readFrom > 0 and lines.len > 0:
    # Zaczynaliśmy czytać od losowego offsetu w środku pliku -- pierwsza
    # "linia" jest prawie na pewno uciętym fragmentem poprzedzającej
    # linii, więc ją odrzucamy zamiast pokazywać połowę słowa.
    lines = lines[1 ..< lines.len]

  if lines.len > n:
    lines = lines[lines.len - n ..< lines.len]
  lines

proc handleLogs(name: string, countArg: string): string =
  if not services.hasKey(name):
    return "ERR nieznana usluga: " & name

  var n = DefaultLogsRequested
  if countArg.len > 0:
    try:
      n = parseInt(countArg)
    except ValueError:
      return "ERR liczba linii musi byc liczba calkowita: '" & countArg & "'"
  if n <= 0: n = DefaultLogsRequested
  if n > MaxLogsRequested: n = MaxLogsRequested

  let path = ServiceLogDir / (name & ".log")
  let lines = tailLines(path, n)
  if lines.len == 0:
    return "OK (brak logu dla '" & name & "' albo jest on pusty)"
  lines.join("\n") & "\nOK"

proc dispatchCommand(line: string): string =
  let parts = line.strip().splitWhitespace()
  if parts.len == 0:
    return "ERR puste polecenie"

  let cmd = parts[0].toLowerAscii()
  case cmd
  of "ping":
    "OK pong"

  of "list":
    var lines: seq[string] = @[]
    for name, svc in services:
      lines.add(name & " " & formatState(svc.state) & " " & $svc.pid & " " & $svc.restartCount)
    lines.add("OK")
    lines.join("\n")

  of "status":
    if parts.len < 2:
      return "ERR uzycie: status <nazwa>"
    let name = parts[1]
    if not services.hasKey(name):
      return "ERR nieznana usluga: " & name
    let svc = services[name]
    "name=" & name & "\n" &
      "state=" & formatState(svc.state) & "\n" &
      "pid=" & $svc.pid & "\n" &
      "restartCount=" & $svc.restartCount & "\n" &
      "OK"

  of "start":
    if parts.len < 2:
      return "ERR uzycie: start <nazwa>"
    let name = parts[1]
    if not services.hasKey(name):
      return "ERR nieznana usluga: " & name
    startService(name)
    "OK"

  of "stop":
    if parts.len < 2:
      return "ERR uzycie: stop <nazwa>"
    let name = parts[1]
    if not services.hasKey(name):
      return "ERR nieznana usluga: " & name
    stopService(name)
    "OK"

  of "restart":
    if parts.len < 2:
      return "ERR uzycie: restart <nazwa>"
    let name = parts[1]
    if not services.hasKey(name):
      return "ERR nieznana usluga: " & name
    stopService(name)
    startService(name)
    "OK"

  of "isolate":
    if parts.len < 2:
      return "ERR uzycie: isolate <target>"
    handleIsolate(parts[1])

  of "reload":
    # Wczytuje ponownie /etc/zenit/services BEZ zrywania działających
    # usług (patrz zsrvpkg/parser.reloadServices), a następnie startuje
    # nowo dodane usługi, które chcą działać w bieżącym targecie.
    # Celowo BEZ `force=true`: reload NIE powinien wskrzeszać usług
    # zatrzymanych jawnie przez `zsrvctl stop` tylko dlatego, że ktoś
    # przeładował konfigurację -- to zaskakiwałoby administratora. Nowe
    # usługi (nigdy jeszcze niezatrzymane, `stoppedByAdmin=false` z
    # definicji) i tak startują normalnie.
    let (added, updated, removed) = reloadServices(ServiceDir)
    let summary = "dodano=" & $added & " zaktualizowano=" & $updated & " usunieto=" & $removed
    log("zsrv: zsrvctl reload -> " & summary)
    applyTarget(currentTarget)
    "OK " & summary

  of "logs":
    if parts.len < 2:
      return "ERR uzycie: logs <nazwa> [N]"
    let countArg = if parts.len >= 3: parts[2] else: ""
    handleLogs(parts[1], countArg)

  else:
    "ERR nieznane polecenie: " & cmd

proc handleControlConnection*(fd: cint) =
  ## Obsługuje pojedyncze połączenie: odczytuje jedną linię polecenia,
  ## wysyła odpowiedź, zamyka gniazdo. Wywoływane z pętli zdarzeń
  ## (zsrvpkg/eventloop) po zaakceptowaniu połączenia na `listenFd`.
  ##
  ## WAŻNE (błąd znaleziony i naprawiony przez rzeczywisty test end-to-end
  ## z `zsrvctl`): gniazda strumieniowe (SOCK_STREAM) NIE gwarantują, że
  ## dane z jednego logicznego zapisu po stronie klienta dotrą w JEDNYM
  ## `read()` po stronie serwera — klient (Crystal `Socket#puts`) wysyła
  ## treść polecenia i kończący znak nowej linii jako DWA OSOBNE
  ## `send()`/`write()`. Pojedyncze `read()` (bez pętli) potrafiło odebrać
  ## TYLKO pierwszą część ("ping" bez "\n"), po czym serwer od razu
  ## odpowiadał i ZAMYKAŁ połączenie — a drugi zapis klienta (sam "\n")
  ## trafiał wtedy w już zamknięte gniazdo, dając `EPIPE`/`SIGPIPE` po
  ## stronie klienta, mimo że polecenie de facto zostało poprawnie
  ## wykonane. Stąd pętla poniżej: czytamy, dopóki nie zobaczymy '\n' w
  ## zebranym buforze (albo bufor się nie zapełni, albo klient zamknie
  ## połączenie ze swojej strony / EOF).
  var buf: array[512, char]
  var total = 0
  var sawNewline = false

  while total < buf.len - 1 and not sawNewline:
    let n = c_read(fd, addr buf[total], csize_t(buf.len - 1 - total))
    if n <= 0:
      break # EOF albo błąd -- przetwarzamy to, co już mamy (jeśli cokolwiek)
    for i in total ..< total + n:
      if buf[i] == '\n':
        sawNewline = true
        break
    total += n

  if total == 0:
    closeConnection(fd)
    return

  buf[total] = '\0'
  let line = $cast[cstring](addr buf[0])
  let response = dispatchCommand(line) & "\n"
  discard c_write(fd, response.cstring, csize_t(response.len))
  closeConnection(fd)
  
