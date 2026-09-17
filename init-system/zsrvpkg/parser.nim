import std/[os, strutils, sequtils, times, tables, sets]
import ./types
import ./state
import ./logger

const
  ServiceDir* = "/etc/zenit/services"
  ServiceExt* = ".zsrv"

proc parseRestartPolicy(s: string): RestartPolicy =
  case s.strip().toLowerAscii()
  of "always": rpAlways
  of "on-failure": rpOnFailure
  else: rpNever

proc parseTargetList(s: string): seq[Target] =
  result = @[]
  for part in s.split(','):
    let t = part.strip().toLowerAscii()
    case t
    of "rescue": result.add(tgRescue)
    of "multi-user": result.add(tgMultiUser)
    else: log("zsrv: nieznany target '" & t & "' w WantedBy")

proc parseByteSize(s: string): int64 =
  ## Obsługuje proste sufiksy K/M/G (binarne, 1024-owe), np. "256M".
  let trimmed = s.strip()
  if trimmed.len == 0: return 0
  let last = trimmed[^1].toUpperAscii()
  if last in {'K', 'M', 'G'}:
    let num = trimmed[0 ..< trimmed.len - 1].parseInt()
    case last
    of 'K': return num.int64 * 1024
    of 'M': return num.int64 * 1024 * 1024
    of 'G': return num.int64 * 1024 * 1024 * 1024
    else: discard
  trimmed.parseInt().int64

proc stripInlineComment(s: string): string =
  ## Obcina komentarz na końcu linii (` # ...`) -- TYLKO jeśli `#` jest
  ## POZA cudzysłowami i poprzedzony spacją/tabulatorem (albo jest
  ## pierwszym znakiem) -- to ostatnie zabezpiecza przed ucięciem
  ## legalnej wartości zawierającej `#` bez spacji przed nim (np. w
  ## niektórych URL-ach czy hasłach). W przeciwieństwie do prawdziwych
  ## plików jednostek systemd (gdzie komentarz może być TYLKO na własnej
  ## linii), ten prosty format zenit-base świadomie wspiera też komentarz
  ## na końcu linii z dyrektywą, bo jest to wygodniejsze przy pisaniu
  ## ręcznie.
  var inSingle = false
  var inDouble = false
  var i = 0
  while i < s.len:
    let c = s[i]
    if c == '\'' and not inDouble:
      inSingle = not inSingle
    elif c == '"' and not inSingle:
      inDouble = not inDouble
    elif c == '#' and not inSingle and not inDouble:
      if i == 0 or s[i - 1] in {' ', '\t'}:
        return s[0 ..< i].strip()
    inc i
  s

proc tokenizeExecLine*(s: string): seq[string] =
  ## Dzieli wartość `ExecStart=` na argv w stylu powłoki -- w
  ## przeciwieństwie do naiwnego `splitWhitespace()` (poprzednio używanego
  ## bezpośrednio w zsrvpkg/supervisor) poprawnie obsługuje argumenty
  ## zawierające spacje, ujęte w pojedyncze lub podwójne cudzysłowy (np.
  ## `ExecStart=/usr/bin/foo --name "moja usluga"` daje DWA argumenty:
  ## `--name` i `moja usluga`, nie cztery) oraz escapowanie `\` poza
  ## cudzysłowami.
  result = @[]
  var current = ""
  var haveCurrent = false
  var i = 0
  while i < s.len:
    let c = s[i]
    case c
    of ' ', '\t':
      if haveCurrent:
        result.add(current)
        current = ""
        haveCurrent = false
      inc i
    of '\'':
      haveCurrent = true
      inc i
      while i < s.len and s[i] != '\'':
        current &= s[i]
        inc i
      if i < s.len: inc i # zamykający '
    of '"':
      haveCurrent = true
      inc i
      while i < s.len and s[i] != '"':
        if s[i] == '\\' and i + 1 < s.len and s[i + 1] in {'"', '\\'}:
          current &= s[i + 1]
          i += 2
        else:
          current &= s[i]
          inc i
      if i < s.len: inc i # zamykający "
    of '\\':
      haveCurrent = true
      if i + 1 < s.len:
        current &= s[i + 1]
        i += 2
      else:
        inc i
    else:
      haveCurrent = true
      current &= c
      inc i
  if haveCurrent:
    result.add(current)

proc parseServiceFile*(path: string): ServiceDef =
  ## Prosty format klucz=wartość, jedna dyrektywa na linię, np.:
  ##
  ##   [Service]
  ##   Name=network
  ##   ExecStart=/usr/lib/zenit/net-up --iface "eth 0"   # komentarz OK
  ##   After=udev
  ##   WantedBy=multi-user
  ##   Restart=on-failure
  ##   RestartSec=2
  ##   StopSec=5
  ##   User=zenit-net
  ##   MemoryMax=256M
  ##   CPUQuota=50
  ##   Environment=LOG_LEVEL=debug
  ##   Environment=FOO=1 BAR=2
  ##
  ## Nagłówki sekcji w stylu systemd (`[Unit]`, `[Service]`, ...) są
  ## rozpoznawane i po cichu pomijane (czysto kosmetyczne grupowanie --
  ## ten format, w przeciwieństwie do systemd, nie nadaje im żadnego
  ## znaczenia; wszystkie znane dyrektywy działają niezależnie od tego,
  ## w jakiej sekcji się znajdą, albo czy w ogóle jakaś sekcja poprzedza
  ## plik) -- dzięki temu pliki skopiowane/zainspirowane plikami
  ## `.service` systemd nie generują fałszywych ostrzeżeń "nieznana
  ## dyrektywa" tylko z powodu nagłówka sekcji.
  ## `Environment=` może wystąpić WIELE razy (wartości się kumulują, tak
  ## jak w systemd) i/albo mieć wiele par `KLUCZ=WARTOSC` oddzielonych
  ## spacją na jednej linii. Jeśli ten sam klucz pojawi się więcej niż
  ## raz, wygrywa OSTATNIE wystąpienie (kolejność zastosowania w
  ## zsrvpkg/supervisor odpowiada kolejności w pliku).
  var memoryMax: int64 = 0
  var cpuQuota: int32 = 0

  result = ServiceDef(
    name: splitFile(path).name,
    execStart: "",
    after: @[],
    wantedBy: @[tgMultiUser], # domyślnie: usługa startuje w multi-user
    restart: rpNever,
    restartSec: 1,
    user: "",
    stopSec: 5,
    environment: @[],
  )

  for line in lines(path):
    let l = line.strip()
    if l.len == 0 or l.startsWith('#'):
      continue
    if l.startsWith('[') and l.endsWith(']'):
      continue # nagłówek sekcji -- patrz komentarz nad tą procedurą
    let parts = l.split('=', 1)
    if parts.len != 2:
      continue
    let key = parts[0].strip()
    let value = stripInlineComment(parts[1].strip())
    case key
    of "Name": result.name = value
    of "ExecStart": result.execStart = value
    of "After": result.after = value.split(',').mapIt(it.strip())
    of "WantedBy": result.wantedBy = parseTargetList(value)
    of "Restart": result.restart = parseRestartPolicy(value)
    of "RestartSec": result.restartSec = parseInt(value)
    of "StopSec": result.stopSec = parseInt(value)
    of "User": result.user = value
    of "MemoryMax": memoryMax = parseByteSize(value)
    of "CPUQuota": cpuQuota = parseInt(value.replace("%", "")).int32
    of "Environment":
      # Jedna albo więcej par KLUCZ=WARTOSC, oddzielonych spacją; walidacja
      # (obecność '=') odbywa się dopiero przy ZASTOSOWANIU w
      # zsrvpkg/supervisor, żeby błąd trafił do logu z kontekstem PID-a
      # usługi, a nie tylko nazwy pliku.
      for pair in tokenizeExecLine(value):
        result.environment.add(pair)
    else:
      log("zsrv: nieznana dyrektywa '" & key & "' w " & path)

  result.limits = newResourceLimits(memoryMax, cpuQuota)

proc loadServices*(dir: string) =
  services.clear()
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
          pid: 0,
          lastStart: fromUnix(0),
          restartCount: 0,
          restartAt: fromUnix(0),
          stopDeadline: fromUnix(0),
        )
        log("zsrv: wczytano definicję usługi '" & def.name & "'")
      except CatchableError as e:
        log("zsrv: błąd parsowania '" & path & "': " & e.msg)

proc reloadServices*(dir: string): tuple[added, updated, removed: int] =
  ## Odpowiednik `loadServices`, ale zachowujący stan RUNTIME istniejących
  ## usług (pid, state, restartCount, lastStart, restartAt, stopDeadline)
  ## zamiast wywoływać `services.clear()` — to, co robi `loadServices`,
  ## jest bezpieczne TYLKO przy starcie systemu (gdy żadna usługa jeszcze
  ## nie działa); wywołane ponownie w trakcie pracy zgubiłoby śledzenie
  ## PID-ów już uruchomionych usług, prowadząc do podwójnego startu albo
  ## utraty nadzoru nad osieroconymi procesami.
  ##
  ## Użycie: `zsrvctl reload` (patrz zsrvpkg/control) — pozwala dodać
  ## nowy plik `.zsrv` (albo zmienić istniejący) i załadować go BEZ
  ## restartu całego PID 1 i bez zrywania już działających usług.
  result = (added: 0, updated: 0, removed: 0)
  if not dirExists(dir):
    log("zsrv: katalog usług '" & dir & "' nie istnieje — pomijam reload")
    return

  var seenNames = initHashSet[string]()

  for kind, path in walkDir(dir):
    if kind == pcFile and path.endsWith(ServiceExt):
      try:
        let def = parseServiceFile(path)
        seenNames.incl(def.name)
        if def.name in services:
          # Usługa już znana -- podmieniamy TYLKO definicję (ExecStart,
          # After, WantedBy, limity itd. mogły się zmienić), zachowując
          # cały stan runtime nietknięty. Zmiana ExecStart/limitów NIE
          # restartuje automatycznie już działającej usługi — zadziała
          # dopiero przy jej kolejnym (re)starcie, tak jak przy zwykłym
          # `systemctl daemon-reload` bez towarzyszącego `restart`.
          var svc = services[def.name]
          svc.def = def
          services[def.name] = svc
          inc result.updated
        else:
          services[def.name] = ServiceRuntime(
            def: def,
            state: ssStopped,
            pid: 0,
            lastStart: fromUnix(0),
            restartCount: 0,
            restartAt: fromUnix(0),
            stopDeadline: fromUnix(0),
          )
          inc result.added
        log("zsrv: reload -- wczytano definicję usługi '" & def.name & "'")
      except CatchableError as e:
        log("zsrv: reload -- błąd parsowania '" & path & "': " & e.msg)

  # Usługi, których plik .zsrv zniknął z katalogu: usuwamy z tabeli TYLKO
  # jeśli są już zatrzymane — usunięcie wciąż DZIAŁAJĄCEJ usługi z
  # tabeli urwałoby jej nadzór (restarty, `stop`/`status` przez zsrvctl),
  # zamieniając ją w proces-sierotę, którym nic już nie zarządza. Zamiast
  # tego zostaje ostrzeżenie w logu — zniknie z tabeli przy KOLEJNYM
  # reload, już po jej zatrzymaniu.
  for name in toSeq(services.keys):
    if name notin seenNames:
      if services[name].state in {ssRunning, ssStarting, ssStopping}:
        log("zsrv: reload -- plik usługi '" & name &
            "' zniknął, ale usługa wciąż działa/zmienia stan -- zostawiam w tabeli do jej zatrzymania")
      else:
        services.del(name)
        inc result.removed
