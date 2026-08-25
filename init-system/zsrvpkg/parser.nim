import std/[os, strutils, sequtils, times]
import ./types
import ./state
import ./log

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

proc parseServiceFile*(path: string): ServiceDef =
  ## Prosty format klucz=wartość, jedna dyrektywa na linię, np.:
  ##
  ##   Name=network
  ##   ExecStart=/usr/lib/zenit/net-up
  ##   After=udev
  ##   WantedBy=multi-user
  ##   Restart=on-failure
  ##   RestartSec=2
  ##   StopSec=5
  ##   User=zenit-net
  ##   MemoryMax=256M
  ##   CPUQuota=50
  ##
  ## TODO: sekcje w stylu systemd ([Unit]/[Service]), komentarze na końcu
  ## linii, cudzysłowy z argumentami zawierającymi spacje.
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
    of "WantedBy": result.wantedBy = parseTargetList(value)
    of "Restart": result.restart = parseRestartPolicy(value)
    of "RestartSec": result.restartSec = parseInt(value)
    of "StopSec": result.stopSec = parseInt(value)
    of "User": result.user = value
    of "MemoryMax": memoryMax = parseByteSize(value)
    of "CPUQuota": cpuQuota = parseInt(value.replace("%", "")).int32
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
