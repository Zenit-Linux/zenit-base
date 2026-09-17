import std/[unittest, os, tables]
import "../init-system/zsrvpkg/parser"
import "../init-system/zsrvpkg/types"
import "../init-system/zsrvpkg/state"

const TmpDir = getTempDir() / "zenit-base-test-service-parser"

proc writeServiceFile(name: string, content: string): string =
  createDir(TmpDir)
  result = TmpDir / name
  writeFile(result, content)

suite "parser.tokenizeExecLine":
  test "proste argumenty rozdzielone spacjami":
    check tokenizeExecLine("/bin/true a b c") == @["/bin/true", "a", "b", "c"]

  test "argument w podwójnym cudzysłowie ze spacją w środku":
    check tokenizeExecLine("""/usr/bin/foo --name "moja usluga"""") ==
      @["/usr/bin/foo", "--name", "moja usluga"]

  test "argument w pojedynczym cudzysłowie":
    check tokenizeExecLine("/bin/echo 'a b c'") == @["/bin/echo", "a b c"]

  test "escapowanie backslashem poza cudzysłowem":
    check tokenizeExecLine("""/bin/echo a\ b c""") == @["/bin/echo", "a b", "c"]

  test "wielokrotne spacje między argumentami nie tworzą pustych tokenów":
    check tokenizeExecLine("/bin/true   a    b") == @["/bin/true", "a", "b"]

  test "pusty łańcuch daje pustą listę":
    check tokenizeExecLine("") == newSeq[string]()

suite "parser.parseServiceFile":
  test "podstawowe dyrektywy":
    let path = writeServiceFile("basic.zsrv", """
Name=network
ExecStart=/usr/lib/zenit/net-up
After=udev
WantedBy=multi-user
Restart=on-failure
RestartSec=2
StopSec=5
User=zenit-net
MemoryMax=256M
CPUQuota=50
""")
    let def = parseServiceFile(path)
    check def.name == "network"
    check def.execStart == "/usr/lib/zenit/net-up"
    check def.after == @["udev"]
    check def.wantedBy == @[tgMultiUser]
    check def.restart == rpOnFailure
    check def.restartSec == 2
    check def.stopSec == 5
    check def.user == "zenit-net"
    check def.limits.memoryMaxBytes == 256 * 1024 * 1024
    check def.limits.cpuQuotaPercent == 50

  test "Environment= pojedyncza para KLUCZ=WARTOSC":
    let path = writeServiceFile("env-single.zsrv", "ExecStart=/bin/true\nEnvironment=LOG_LEVEL=debug\n")
    check parseServiceFile(path).environment == @["LOG_LEVEL=debug"]

  test "Environment= wiele par na jednej linii":
    let path = writeServiceFile("env-multi.zsrv", "ExecStart=/bin/true\nEnvironment=FOO=1 BAR=2\n")
    check parseServiceFile(path).environment == @["FOO=1", "BAR=2"]

  test "Environment= kumuluje się przy wielu wystapieniach dyrektywy":
    let path = writeServiceFile("env-repeat.zsrv", "ExecStart=/bin/true\nEnvironment=A=1\nEnvironment=B=2\n")
    check parseServiceFile(path).environment == @["A=1", "B=2"]

  test "Environment= z wartoscia zawierajaca spacje w cudzyslowie":
    let path = writeServiceFile("env-quoted.zsrv", """
ExecStart=/bin/true
Environment=GREETING="hello world"
""")
    check parseServiceFile(path).environment == @["GREETING=hello world"]

  test "brak Environment= daje pusta liste":
    let path = writeServiceFile("no-env.zsrv", "ExecStart=/bin/true\n")
    check parseServiceFile(path).environment.len == 0

  test "nazwa domyślna z nazwy pliku, gdy brak Name=":
    let path = writeServiceFile("moja-usluga.zsrv", "ExecStart=/bin/true\n")
    check parseServiceFile(path).name == "moja-usluga"

  test "domyślny WantedBy to multi-user, gdy nie podano":
    let path = writeServiceFile("brak-wantedby.zsrv", "ExecStart=/bin/true\n")
    check parseServiceFile(path).wantedBy == @[tgMultiUser]

  test "wiele targetów w WantedBy (oddzielone przecinkiem)":
    let path = writeServiceFile("multi-target.zsrv", """
ExecStart=/bin/true
WantedBy=rescue, multi-user
""")
    check parseServiceFile(path).wantedBy == @[tgRescue, tgMultiUser]

  test "puste linie i komentarze na CAŁEJ linii są ignorowane":
    let path = writeServiceFile("comments.zsrv", """
# to jest komentarz na calej linii
ExecStart=/bin/true

# kolejny komentarz
After=udev
""")
    let def = parseServiceFile(path)
    check def.execStart == "/bin/true"
    check def.after == @["udev"]

  test "nagłówki sekcji [Unit]/[Service] są pomijane (kompatybilność z systemd)":
    let path = writeServiceFile("sections.zsrv", """
[Unit]
[Service]
Name=network
ExecStart=/bin/true
""")
    let def = parseServiceFile(path)
    check def.name == "network"
    check def.execStart == "/bin/true"

  test "komentarz na końcu linii z dyrektywą":
    let path = writeServiceFile("inline-comment.zsrv", """
Name=network   # nazwa uslugi
RestartSec=3   # sekundy
""")
    let def = parseServiceFile(path)
    check def.name == "network"
    check def.restartSec == 3

  test "ExecStart z cudzysłowionym argumentem zawierającym spację, wraz z komentarzem":
    let path = writeServiceFile("execstart-quoted.zsrv", """
ExecStart=/usr/lib/zenit/net-up --iface "eth 0"   # komentarz
""")
    let def = parseServiceFile(path)
    check def.execStart == """/usr/lib/zenit/net-up --iface "eth 0""""
    check tokenizeExecLine(def.execStart) == @["/usr/lib/zenit/net-up", "--iface", "eth 0"]

  test "'#' bez poprzedzającej spacji NIE jest traktowany jako komentarz":
    # Broni się przed ucięciem legalnej wartości zawierającej znak '#'
    # bez spacji przed nim (np. w niektórych identyfikatorach/URL-ach).
    let path = writeServiceFile("hash-in-value.zsrv", """
ExecStart=/bin/echo wartosc#bez-spacji
""")
    check parseServiceFile(path).execStart == "/bin/echo wartosc#bez-spacji"

  test "MemoryMax bez sufiksu to bajty wprost":
    let path = writeServiceFile("membytes.zsrv", """
ExecStart=/bin/true
MemoryMax=1024
""")
    check parseServiceFile(path).limits.memoryMaxBytes == 1024

  test "nieznana dyrektywa nie wywala parsowania (tylko log)":
    let path = writeServiceFile("unknown-directive.zsrv", """
ExecStart=/bin/true
CalkiemNieznanaDyrektywa=cokolwiek
""")
    check parseServiceFile(path).execStart == "/bin/true"

suite "parser.reloadServices":
  setup:
    services.clear()

  test "nowa usluga zostaje dodana ze stanem 'stopped'":
    let dir = TmpDir / "reload-add"
    createDir(dir)
    writeFile(dir / "svc.zsrv", "ExecStart=/bin/true\n")
    let (added, updated, removed) = reloadServices(dir)
    check added == 1
    check updated == 0
    check removed == 0
    check services["svc"].state == ssStopped
    removeDir(dir)

  test "reload zachowuje stan runtime dzialajacej uslugi przy zmianie definicji":
    let dir = TmpDir / "reload-preserve"
    createDir(dir)
    writeFile(dir / "svc.zsrv", "ExecStart=/bin/true\n")
    discard reloadServices(dir)

    # Symulujemy, że usługa jest już uruchomiona (tak jak zrobiłby to
    # supervisor.startService po fork()+exec()).
    var svc = services["svc"]
    svc.state = ssRunning
    svc.pid = 4321
    svc.restartCount = 2
    services["svc"] = svc

    # Zmieniamy definicję na dysku i reloadujemy ponownie -- stan runtime
    # powinien przetrwać, zmienia się tylko `def`.
    writeFile(dir / "svc.zsrv", "ExecStart=/bin/false\n")
    let (added, updated, removed) = reloadServices(dir)
    check added == 0
    check updated == 1
    check removed == 0
    check services["svc"].state == ssRunning
    check services["svc"].pid == 4321
    check services["svc"].restartCount == 2
    check services["svc"].def.execStart == "/bin/false"
    removeDir(dir)

  test "usunieta, zatrzymana usluga znika z tabeli":
    let dir = TmpDir / "reload-remove-stopped"
    createDir(dir)
    writeFile(dir / "svc.zsrv", "ExecStart=/bin/true\n")
    discard reloadServices(dir)
    check "svc" in services

    removeFile(dir / "svc.zsrv")
    let (added, updated, removed) = reloadServices(dir)
    check added == 0
    check updated == 0
    check removed == 1
    check "svc" notin services
    removeDir(dir)

  test "usunieta, ALE wciaz dzialajaca usluga NIE znika z tabeli":
    let dir = TmpDir / "reload-keep-running"
    createDir(dir)
    writeFile(dir / "svc.zsrv", "ExecStart=/bin/true\n")
    discard reloadServices(dir)
    var svc = services["svc"]
    svc.state = ssRunning
    svc.pid = 999
    services["svc"] = svc

    removeFile(dir / "svc.zsrv")
    let (added, updated, removed) = reloadServices(dir)
    check removed == 0
    check "svc" in services
    check services["svc"].state == ssRunning
    removeDir(dir)

removeDir(TmpDir)
echo "\nWszystkie testy parser.nim (service) przeszły pomyślnie."
