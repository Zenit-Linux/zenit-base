import std/[os, strutils]
import ./types
import ./logger

const CgroupRoot = "/sys/fs/cgroup/zenit"
const CgroupSysRoot = "/sys/fs/cgroup"

proc ensureCgroupRootExists() =
  try:
    if not dirExists(CgroupRoot):
      createDir(CgroupRoot)
  except OSError as e:
    log("cgroups: nie można utworzyć '" & CgroupRoot & "': " & e.msg)

proc enableSubtreeControl*() =
  ## Cgroups v2 wymaga jawnego "delegowania" kontrolerów w dół hierarchii:
  ## kontroler dostępny w cgroup.controllers rodzica trzeba dopisać do
  ## cgroup.subtree_control, zanim dzieci będą mogły z niego korzystać.
  ## Wywoływane raz, przy starcie zsrv, zanim jakakolwiek usługa dostanie
  ## własną cgroupę.
  ensureCgroupRootExists()
  for path in [CgroupSysRoot / "cgroup.subtree_control", CgroupRoot / "cgroup.subtree_control"]:
    try:
      writeFile(path, "+memory +cpu")
    except OSError as e:
      log("cgroups: nie udalo sie wlaczyc kontrolerow w '" & path & "': " & e.msg &
          " (limity MemoryMax=/CPUQuota= moga nie dzialac)")

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
  ## Usuwa cgroupę usługi, o ile cgroup.procs jest puste (rmdir na
  ## niepustej cgroupie zawiedzie w jądrze — nie jest to błąd krytyczny,
  ## po prostu spróbujemy ponownie przy następnym restarcie usługi).
  let path = serviceCgroupPath(serviceName)
  try:
    let procsContent = readFile(path / "cgroup.procs").strip()
    if procsContent.len == 0 and dirExists(path):
      removeDir(path)
  except OSError:
    discard # cgroupa nie istnieje / wciąż zawiera procesy — pomijamy
