import std/[unittest, tables, times]
import "../init-system/zsrvpkg/depgraph"
import "../init-system/zsrvpkg/state"
import "../init-system/zsrvpkg/types"

proc mkService(name: string, after: seq[string]): ServiceRuntime =
  ServiceRuntime(
    def: ServiceDef(
      name: name,
      execStart: "/bin/true",
      after: after,
      wantedBy: @[tgMultiUser],
      restart: rpNever,
      restartSec: 1,
      user: "",
      stopSec: 5,
      limits: newResourceLimits(),
    ),
    state: ssStopped,
    pid: 0,
    lastStart: fromUnix(0),
    restartCount: 0,
    restartAt: fromUnix(0),
    stopDeadline: fromUnix(0),
  )

proc setupServices(defs: openArray[(string, seq[string])]) =
  services.clear()
  for (name, after) in defs:
    services[name] = mkService(name, after)

suite "depgraph.topologicalStartOrder":
  test "brak zależności -- kolejność alfabetyczna (deterministyczna)":
    setupServices({"c": newSeq[string](), "a": newSeq[string](), "b": newSeq[string]()})
    check topologicalStartOrder(@["c", "a", "b"]) == @["a", "b", "c"]

  test "prosty łańcuch A <- B <- C (After=)":
    # "siec" zależy od "udev" (After=udev), "dns" zależy od "siec"
    setupServices({
      "siec": @["udev"],
      "udev": newSeq[string](),
      "dns": @["siec"],
    })
    let order = topologicalStartOrder(@["siec", "udev", "dns"])
    check order == @["udev", "siec", "dns"]

  test "kilka usług bez wzajemnych zależności + jedna zależna od dwóch":
    setupServices({
      "a": newSeq[string](),
      "b": newSeq[string](),
      "c": @["a", "b"],
    })
    let order = topologicalStartOrder(@["a", "b", "c"])
    check order.find("a") < order.find("c")
    check order.find("b") < order.find("c")
    check order[^1] == "c"

  test "zależność spoza aktywnego zestawu usług jest ignorowana (nie blokuje)":
    # "siec" ma After=nieaktywna-usluga, ale ta usługa NIE jest w
    # przekazanym zestawie `names` -- nie powinno to zablokować "siec".
    setupServices({"siec": @["nieaktywna-usluga"]})
    check topologicalStartOrder(@["siec"]) == @["siec"]

  test "cykl zależności -- nie wisi w nieskończoność, dodaje resztę na końcu":
    # a zależy od b, b zależy od a: klasyczny cykl.
    setupServices({
      "a": @["b"],
      "b": @["a"],
      "niezalezna": newSeq[string](),
    })
    let order = topologicalStartOrder(@["a", "b", "niezalezna"])
    check order.len == 3
    # "niezalezna" (bez zależności) startuje przed cyklicznym rejestrem
    check order[0] == "niezalezna"
    # obie usługi z cyklu i tak trafiają do wyniku (na końcu), zamiast
    # zawieszać cały rozruch systemu
    check "a" in order
    check "b" in order

  test "pusty zestaw usług":
    setupServices({"x": newSeq[string]()}) # cokolwiek w services, ale names=@[] poniżej
    check topologicalStartOrder(newSeq[string]()) == newSeq[string]()

echo "\nWszystkie testy depgraph.nim przeszły pomyślnie."
