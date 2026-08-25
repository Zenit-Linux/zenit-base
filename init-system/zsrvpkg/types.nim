import std/times

type
  RestartPolicy* = enum
    rpNever, rpAlways, rpOnFailure

  ServiceState* = enum
    ssStopped, ssStarting, ssRunning, ssFailed, ssStopping

  Target* = enum
    tgRescue    = "rescue"     # minimalny zestaw usług, powłoka ratunkowa
    tgMultiUser = "multi-user" # pełny, standardowy zestaw usług

  ResourceLimits* = object
    ## Limity zasobów przekazywane do cgroups v2 (patrz zsrvpkg/cgroups).
    ## Pole `0`/"" oznacza "brak limitu" (nie ustawiamy odpowiedniego pliku).
    memoryMaxBytes: int64
    cpuQuotaPercent: int32 # np. 50 = maks. 50% jednego rdzenia; 0 = brak limitu

  ServiceDef* = object
    name*:       string
    execStart*:  string
    after*:      seq[string] # nazwy usług, które muszą wystartować wcześniej
    wantedBy*:   seq[Target] # w jakich targetach usługa ma być uruchamiana
    restart*:    RestartPolicy
    restartSec*: int
    user*:       string       # nazwa użytkownika do setuid/setgid (opcjonalnie)
    limits*:     ResourceLimits
    stopSec*:    int          # limit czasu na reakcję na SIGTERM przed SIGKILL

  ServiceRuntime* = object
    def*:          ServiceDef
    state*:        ServiceState
    pid*:          int32
    lastStart*:    Time
    restartCount*: int
    restartAt*:    Time # kiedy uruchomić ponownie po awarii (jeśli oczekuje)
    stopDeadline*: Time # kiedy wysłać SIGKILL, jeśli usługa nie zareagowała na SIGTERM

proc newResourceLimits*(memoryMaxBytes: int64 = 0, cpuQuotaPercent: int32 = 0): ResourceLimits =
  ResourceLimits(memoryMaxBytes: memoryMaxBytes, cpuQuotaPercent: cpuQuotaPercent)

proc memoryMaxBytes*(r: ResourceLimits): int64 = r.memoryMaxBytes
proc cpuQuotaPercent*(r: ResourceLimits): int32 = r.cpuQuotaPercent
