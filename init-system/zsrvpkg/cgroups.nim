import std/[os, strutils]
import ./types
import ./log

const CgroupRoot = "/sys/fs/cgroup/zenit"

proc ensureCgroupRootExists() =
  try:
    if not dirExists(CgroupRoot):
      createDir(CgroupRoot)
  except OSError as e:
    log("cgroups: nie można utworzyć '" & CgroupRoot & "': " & e.msg)

proc serviceCgroupPath(serviceName: string): string =
  CgroupRoot / serviceName

proc createServiceCgroup*(serviceName: string, limits: ResourceLimits) =
  ## Tworzy dedykowaną cgroupę dla usługi i zapisuje w niej limity zasobów,
  ## jeśli zostały zdefiniowane w pliku usługi (MemoryMax=/CPUQuota=).
  ensureCgroupRootExists()
  let path = serviceCgroupPath(serviceName)

  try:
    if not dirExists(path):
      createDir(path)
  except OSError as e:
    log("cgroups: nie można utworzyć cgroupy dla '" & serviceName & "': " & e.msg)
    return

  if limits.memoryMaxBytes() > 0:
    try:
      writeFile(path / "memory.max", $limits.memoryMaxBytes())
    except OSError as e:
      log("cgroups: nie można ustawić memory.max dla '" & serviceName & "': " & e.msg)

  if limits.cpuQuotaPercent() > 0:
    # Format cpu.max to "<quota> <period>" w mikrosekundach; period domyślnie
    # 100000us (100ms), więc quota = period * procent / 100.
    let period = 100_000
    let quota  = (period * limits.cpuQuotaPercent().int) div 100
    try:
      writeFile(path / "cpu.max", $quota & " " & $period)
    except OSError as e:
      log("cgroups: nie można ustawić cpu.max dla '" & serviceName & "': " & e.msg)

proc attachPidToCgroup*(serviceName: string, pid: int32) =
  ## Wywoływane w PROCESIE POTOMNYM tuż przed execvp, aby proces (i wszystko,
  ## co z niego powstanie) znalazł się pod kontrolą odpowiedniej cgroupy.
  let path = serviceCgroupPath(serviceName) / "cgroup.procs"
  try:
    writeFile(path, $pid)
  except OSError:
    discard # brak cgroups v2 w systemie / brak uprawnień — nie blokujemy startu usługi

proc removeCgroup*(serviceName: string) =
  ## TODO: usuwanie cgroupy po zatrzymaniu usługi wymaga, aby cgroup.procs
  ## było puste (wszystkie procesy zakończone) — dziś nie czyścimy katalogów,
  ## co przy wielu restartach pozostawia puste cgroupy w drzewie.
  discard
