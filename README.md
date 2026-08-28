# Zenit Linux

**Zenit Linux** to dystrybucja Linuksa budowana od zera, uzależniona od GNU
(libc, toolchain itd.), ale zastępująca klasyczne narzędzia coreutils
własnymi, nowoczesnymi odpowiednikami — a docelowo także własnym
bootloaderem i systemem init.

## Filozofia

Zamiast klonować `coreutils` 1:1, Zenit pisze każde narzędzie od nowa,
w języku dobranym do jego charakteru, z naciskiem na:

- czytelne, kolorowe komunikaty błędów,
- bezpieczniejsze zachowania domyślne (np. `dl` domyślnie przenosi do kosza,
  a `ar` odrzuca wpisy archiwum ze ścieżkami bezwzględnymi lub `..`),
- nowoczesny, spójny interfejs CLI (`--help`, `--version`, długie i krótkie flagi),
- komponenty systemowe (`zboot`, `zsrv`, `zesh`) podzielone na małe,
  jednoznacznie odpowiedzialne moduły zamiast monolitycznych plików.

Cały projekt jest na wczesnym etapie 0.1 — każdy komponent ma numer wersji
`0.1.0` niezależnie od tego, ile funkcji już zaimplementowano.

## Narzędzia CLI

Wszystkie narzędzia CLI są napisane w **Crystalu**. Powłoka `zesh` oraz
komponenty systemowe (`zboot`, `zsrv`) są w **Nim**.

| Narzędzie | Zastępuje     | Status         | Opis                                          |
|-----------|---------------|----------------|------------------------------------------------|
| `zesh`    | `bash`        | działa (Nim)   | powłoka: potoki, job control, `$(...)`          |
| `about`   | `uname`       | działa         | informacje o systemie                           |
| `cr`      | `mkdir`       | działa         | tworzenie katalogów                             |
| `dl`      | `rm`          | działa         | usuwanie plików/katalogów (z koszem)            |
| `mk`      | `touch`       | działa         | tworzenie plików / aktualizacja czasu           |
| `ow`      | `chown`       | działa         | zmiana właściciela                              |
| `gr`      | `chgrp`       | działa         | zmiana grupy                                    |
| `pm`      | `chmod`       | działa         | zmiana uprawnień                                |
| `rm`      | `mv`          | działa         | przenoszenie / zmiana nazwy                     |
| `echo`    | `echo`        | działa         | wypisywanie tekstu (`-n`, `-e`)                 |
| `sp`      | `ls`          | szkielet+      | listowanie: kolory, `-R`, sortowanie po rozmiarze |
| `kp`      | `cp`          | szkielet       | kopiowanie plików/katalogów                     |
| `wp`      | `cat`         | szkielet       | wypisywanie zawartości plików                   |
| `sz`      | `grep`        | szkielet+      | wyszukiwanie: kontekst `-A/-B/-C`, kolorowanie  |
| `zn`      | `find`        | szkielet+      | wyszukiwanie: `--exec`, filtry rozmiaru/czasu   |
| `lb`      | `wc`          | szkielet       | liczenie linii / słów / bajtów                  |
| `wz`      | `ln`          | szkielet       | dowiązania twarde i symboliczne                 |
| `pr`      | `ps`          | szkielet       | listowanie procesów (z `/proc`)                 |
| `df`      | `df`          | szkielet       | zajętość miejsca na dyskach (statvfs)           |
| `du`      | `du`          | szkielet       | zajętość katalogów (rekurencyjnie)              |
| `zb`      | `kill`        | szkielet       | wysyłanie sygnałów do procesów ("zabij")        |
| `fr`      | `head`/`tail` | szkielet       | podgląd początku/końca pliku, `-f` ("fragment") |
| `so`      | `sort`        | szkielet       | sortowanie linii (leksykograficznie/numerycznie)|
| `un`      | `uniq`        | szkielet       | usuwanie sąsiadujących duplikatów linii         |
| `ar`      | `tar`         | działa (ustar) | archiwizacja, format ustar + gzip (`-z`)        |
| `gdz`     | `which`       | szkielet       | lokalizacja polecenia w `$PATH` ("gdzie")       |
| `en`      | `env`         | szkielet+      | zmienne środowiskowe, `-i` (czyste środowisko)  |
| `id`      | `id`          | szkielet+      | UID/GID z rozwiązywaniem nazw (getpwuid/getgrgid) |
| `kt`      | `whoami`      | szkielet+      | nazwa użytkownika przez getpwuid(getuid()) ("kto") |
| `hn`      | `hostname`    | szkielet       | odczyt nazwy hosta                              |
| `ro`      | `diff`        | szkielet       | porównywanie plików tekstowych (LCS) ("różnice")|
| `xa`      | `xargs`       | szkielet       | budowanie i uruchamianie poleceń z stdin        |
| `zdb`     | `gdb`         | szkielet+      | debugger `ptrace(2)` z symbolami ELF i deasemblacją |
| `pf`      | `printf`      | szkielet       | formatowane wypisywanie (`%s`/`%d`/`%f`)        |
| `wm`      | `free`        | szkielet       | zajętość RAM/swap z `/proc/meminfo` ("wolna pamięć") |
| `up`      | `uptime`      | szkielet       | czas działania i obciążenie systemu             |
| `ni`      | `nice`        | szkielet       | uruchomienie polecenia ze zmienionym priorytetem |

36 narzędzi łącznie. „Szkielet” oznacza gotowy interfejs CLI i podstawową
ścieżkę działania z opisanymi w kodzie brakami (`TODO`); „szkielet+”
oznacza, że dodatkowo zaimplementowano część zaawansowanych opcji.

> Historia: `cr`, `dl` i `mk` były pierwotnie zapisane jako pliki `.cr`
> zawierające kod źródłowy Nim (pomyłka nazewnicza). Zostały przepisane na
> właściwy Crystal, zachowując pełną funkcjonalność oryginału.

> Uwaga: `echo` zostało dodane jako uzupełnienie luki — wcześniejsze
> wersje repo i dokumentacji zakładały jego istnienie (np. w przykładach
> `zesh`), ale nikt nigdy go nie napisał. `zesh` nie ma wbudowanego
> `echo` — deleguje do zewnętrznego programu w `$PATH`, tak jak każda
> klasyczna powłoka uniksowa.

## Komponenty systemowe (Nim) — podzielone na moduły

### `zboot` — bootloader (UEFI, higher-half, uprawnienia per-segment)

**Ten etap celuje wyłącznie w UEFI.** Wsparcie dla klasycznego BIOS jest
świadomie odłożone i ma trafić jako **osobny plugin** implementujący
formalny interfejs `BootBackend` (patrz `bootloader/zbootpkg/backend.nim`).

```
bootloader/
├── zboot.nim                # punkt wejścia UEFI (efiMain) — spina moduły
└── zbootpkg/
    ├── uefi_types.nim         # struktury UEFI (System Table, Boot Services, protokoły plików)
    ├── console.nim              # wypisywanie tekstu (ConOut), panic()
    ├── memory.nim                 # GetMemoryMap z pełną pętlą ponawiania (BUFFER_TOO_SMALL)
    ├── filesystem.nim               # odczyt obrazu jądra z ESP, GetInfo -> dokładny rozmiar bufora
    ├── elf.nim                        # parsowanie ELF64 + kopiowanie segmentów do fizycznej bazy
    ├── graphics.nim                     # Graphics Output Protocol — framebuffer dla jądra
    ├── paging.nim                         # WŁASNE tablice stron: identity map (2 MiB) + jądro (4 KiB, per-segment R/W/X)
    ├── handoff.nim                          # BootInfo, przełączenie stosu i skok do jądra
    └── backend.nim                            # formalny interfejs BootBackend (plugin BIOS w przyszłości)
```

**Higher-half + uprawnienia per-segment**: `zbootpkg/elf` wyznacza
rozpiętość segmentów PT_LOAD, alokuje spójny region fizyczny
(`AllocatePages`) i kopiuje tam segmenty zachowując ich względne
odległości z linkowania. `zbootpkg/paging` buduje WŁASNE tablice stron
(PML4/PDPT/PD/PT): identity mapping niskiej pamięci stronami 2 MiB (dla
buforów zboot) oraz **każdy segment jądra mapowany OSOBNO stronami 4 KiB**
z uprawnieniami odczytanymi z `p_flags` ELF — sekcja `.text` dostaje R+X
(bez W), `.data`/`.bss` dostają R+W (bez X), zamiast jednego zbyt
szerokiego mapowania R+W+X dla całego jądra naraz. Przed użyciem bitu NX
włączane jest `EFER.NXE` (inaczej ustawienie NX przy wyłączonym NXE
powoduje `#GP` zamiast zablokować wykonywanie). Przełączenie `CR3`
następuje dopiero **po** `ExitBootServices` (przed tym firmware polega na
własnych tablicach stron).

Do zrobienia: wyliczanie `identityMapGiB` dynamicznie z mapy pamięci
zamiast stałej 4 GiB, wybór trybu graficznego o najwyższej rozdzielczości
przez `QueryMode`/`SetMode`.

### `zsrv` — system init (PID 1)

```
init-system/
├── zsrv.nim                 # punkt wejścia — spina moduły
└── zsrvpkg/
    ├── types.nim               # ServiceDef, ServiceRuntime, ResourceLimits, Target
    ├── state.nim                 # globalny stan: tabela usług, aktywny target
    ├── logger.nim                  # logowanie z rotacją pliku
    ├── parser.nim                    # parsowanie *.zsrv (User=, MemoryMax=, CPUQuota=, StopSec=)
    ├── depgraph.nim                     # sortowanie topologiczne zależności (After=), algorytm Kahna
    ├── cgroups.nim                        # limity zasobów przez cgroups v2 + subtree_control
    ├── supervisor.nim                       # start/stop/restart, dropPrivileges, setsid, grupy procesów
    ├── target.nim                              # target startowy + przełączanie w locie (/run/zenit/target)
    └── eventloop.nim                             # pętla epoll + signalfd
```

**Grupy procesów i przełączanie targetu w locie** (nowość): każda usługa
dostaje własne PGID przez `setsid()` w procesie potomnym — dzięki temu
`SIGTERM`/`SIGKILL` trafiają do **całej grupy procesów** usługi
(`kill(-pid, sygnał)`), nie tylko do bezpośredniego procesu potomnego, więc
dzieci uruchomione przez usługę też są poprawnie zatrzymywane. Operator
(albo przyszłe `zsrvctl isolate TARGET`) może przełączyć target w locie,
bez restartu: `echo rescue > /run/zenit/target && kill -HUP 1` — `zsrv`
odczyta plik przy `SIGHUP`, zmieni `currentTarget` i **zatrzyma usługi
spoza nowego targetu** (wcześniej `applyTarget` tylko dokładał usługi,
nigdy nie zatrzymywał).

Funkcje: cgroups v2 z `subtree_control`, logi per-usługa w
`/var/log/zenit/<usługa>.log`, uruchamianie na innym użytkowniku
(`User=` → `setgid`+`setuid`), dwufazowe zamykanie (`SIGTERM` →
`SIGKILL` po `StopSec=`), pętla zdarzeń na `epoll`+`signalfd`.

**Testowane** w `tests/test_depgraph.nim` (sortowanie topologiczne) i
`tests/test_service_parser.nim` (parsowanie dyrektyw `.zsrv`).

### `zesh` — powłoka

```
zesh/
├── zesh.nim                 # punkt wejścia, pętla REPL — spina moduły
└── zeshpkg/
    ├── state.nim               # zmienne, aliasy, historia, ostatni kod wyjścia
    ├── vars.nim                  # $NAME/${NAME}/$?/$(polecenie), lokalne vs eksportowane
    ├── cmdhistory.nim              # ~/.zesh_history, odwołania !!/!n
    ├── lexer.nim                     # tokenizacja (cudzysłowy, operatory, & w tle, $(...))
    ├── parser.nim                      # tokeny -> potoki -> instrukcje
    ├── jobcontrol.nim                    # kontrola zadań w tle (&, jobs, fg)
    ├── builtins.nim                        # polecenia wbudowane (alias, type, fg, jobs, ...)
    ├── exec.nim                              # fork/pipe/dup2/execvp, rozwijanie aliasów
    ├── interpreter.nim                          # sekwencje `;`, warunki `&&`/`||`, hook $(...)
    └── prompt.nim                                  # budowanie promptu
```

**Substytucja poleceń `$(...)`** (nowość): `polecenie1 $(polecenie2 arg)`
uruchamia `polecenie2` przez pełny cykl `runLine` (więc obsługuje własne
potoki/przekierowania/wbudowane polecenia), z `STDOUT_FILENO` tymczasowo
przekierowanym na potok przez `dup2` — wynik (bez końcowych znaków nowej
linii, zgodnie z POSIX) trafia w miejsce `$(...)`. Ponieważ moduł
`zeshpkg/vars` jest niskopoziomowy i nie może bezpośrednio importować
`zeshpkg/interpreter` (powstałby cykl: `vars -> interpreter -> lexer ->
vars`), podłączenie następuje przez **wstrzyknięty hook**
(`vars.commandSubstitutionHook`), ustawiany raz przez
`interpreter.setupCommandSubstitution()` przy starcie `zesh` — klasyczny
wzorzec odwrócenia zależności na obejście cyklu importów.

**Naprawiony błąd**: poprzednia wersja rozwijała niecudzysłowione `$NAME`
**znak po znaku** (`expandVars($c)` w pętli), więc `expandVars("$")` samo
w sobie nigdy nie widziało kolejnych znaków nazwy zmiennej —
`echo $HOME` (bez cudzysłowu) nigdy się nie rozwijało, działało tylko
`echo "$HOME"`. Naprawione przez buforowanie ciągłych znaków
niecudzysłowionych w `unquotedRun` i rozwijanie ich razem, przy granicy
słowa — a nie osobno dla każdego znaku. Przy okazji naprawiono też, że
spacja **wewnątrz** `$(polecenie z argumentami)` błędnie kończyła token —
`$(` jest teraz połykane w całości (licząc zagnieżdżone nawiasy) w
głównej pętli tokenizera, zanim reszta znaków zostanie zinterpretowana.

> Uwaga historyczna: moduły `history.nim` i `jobs.nim` (analogicznie
> `zsrvpkg/log.nim`) zostały przemianowane na `cmdhistory.nim`,
> `jobcontrol.nim` i `logger.nim` — Nim traktuje moduł i zmienną/proc o
> identycznej nazwie jako kolizję, co blokowało kompilację.

**Testowane** w `tests/test_lexer.nim` (w tym test na `$(...)` ze spacją
w środku) i `tests/test_parser.nim`.

## Znane naprawione błędy kompilacji

Przy pierwszych próbach `nimble build` na czystym środowisku wyszły na
jaw dwa systematyczne błędy, oba już naprawione i opisane tu, żeby
tłumaczyć, dlaczego kod wygląda tak, a nie inaczej, w kilku miejscach:

1. **Brak `import std/tables`**: Nim wymaga BEZPOŚREDNIEGO importu
   `std/tables` w każdym module wołającym `hasKey`/`mgetOrPut`/`[]` na
   typie `Table`, nawet jeśli inny zaimportowany moduł eksportuje samą
   zmienną tego typu. Dotknęło to `zeshpkg/vars.nim`, `builtins.nim`,
   `exec.nim` oraz `zsrvpkg/parser.nim`, `supervisor.nim` — wszystkie
   naprawione.
2. **Przechwytywanie `result` w zagnieżdżonym `proc`**: Nim zabrania
   zagnieżdżonemu `proc` (domknięciu) przechwytywania niejawnej zmiennej
   `result` ze względów bezpieczeństwa pamięci. Dotknęło to
   `zeshpkg/lexer.tokenize` i `zeshpkg/parser.splitStatements` — obie
   naprawione przez użycie jawnej zmiennej lokalnej zwracanej na końcu
   zamiast niejawnego `result`.

## Struktura repozytorium

```
zenit-linux/
├── shard.yml                  # definicje WSZYSTKICH narzędzi Crystal (36 narzędzi)
├── zenit_base.nimble           # definicje komponentów Nim (zesh, zboot, zsrv) + zadania test/install
├── build.janet                  # orkiestrator budowy całości (+ `-- test`, `-- install`)
├── scripts/
│   ├── install.sh                # kopiuje zbudowane binaria do PREFIX/bin (domyślnie /usr/local/bin)
│   └── uninstall.sh                # usuwa je z powrotem
├── tests/                           # testy jednostkowe Nim (uruchamiane przez `nimble test`)
├── spec/                              # testy integracyjne Crystal (uruchamiane przez `crystal spec`)
├── .github/workflows/
│   ├── build-all.yml                   # CI: buduje i pakuje wszystko
│   ├── build-tools.yml                  # CI: narzędzia CLI (Crystal + zesh)
│   ├── build-bootloader.yml              # CI: zboot (UEFI, BOOTX64.EFI, test w QEMU/OVMF)
│   ├── build-init-system.yml              # CI: zsrv
│   └── test.yml                            # CI: testy jednostkowe + integracyjne
├── zesh/                                     # powłoka (Nim, moduły w zeshpkg/)
├── bootloader/                                 # bootloader UEFI (Nim, moduły w zbootpkg/)
├── init-system/                                  # system init / PID 1 (Nim, moduły w zsrvpkg/)
└── tools/                                          # wszystkie narzędzia CLI (Crystal)
    └── <nazwa>/src/<nazwa>.cr
```

## Budowanie

Wymagania: Nim ≥ 2.0, Crystal ≥ 1.10, Janet, GNU toolchain, a dla
bootloadera dodatkowo krzyżowy toolchain UEFI: `gcc-mingw-w64-x86-64`
(oraz opcjonalnie OVMF + QEMU do testów rozruchu).

```bash
# Powłoka zesh (Nim) — kompiluje zesh.nim wraz z modułami z zeshpkg/
nimble buildShell

# System init zsrv (Nim) — kompiluje zsrv.nim wraz z modułami z zsrvpkg/
nimble buildInit

# Bootloader zboot (Nim, UEFI) -> bootloader/BOOTX64.EFI
nimble buildBootloader

# Wszystkie komponenty Nim naraz
nimble buildAll

# Narzędzia CLI (Crystal) — 36 narzędzi zdefiniowanych w shard.yml
shards install
shards build --release

# Albo całość naraz, przez orkiestrator:
janet build.janet
```

Nazwa pakietu nimble (`zenit_base`) celowo używa podkreślnika zamiast
myślnika — Nimble odrzuca myślniki w nazwach pakietów jako nieprawidłowe.

Wynikowe binaria trafiają do katalogu `dist/`.

## Testy

```bash
# Testy jednostkowe komponentów Nim (parsowanie, sortowanie zależności,
# tokenizacja) — czysta logika, bez potrzeby roota/PID 1/forkowania:
nimble test

# Testy integracyjne narzędzi Crystal — wymagają wcześniejszego builda:
shards build --release
crystal spec

# Albo oba naraz przez orkiestrator:
janet build.janet -- test
```

Zakres testów jest **reprezentatywny, nie wyczerpujący**: `tests/`
pokrywa sortowanie topologiczne zależności zsrv, parsowanie plików
`.zsrv`, tokenizację (w tym `$(...)` ze spacją w środku) i parsowanie
poleceń zesh; `spec/` pokrywa próbkę narzędzi CLI (`cr`, `mk`, `dl`,
`wp`, `so`, `un`, `lb`, `id`, `kt`, `ar`, `zn`, `echo`).

## Instalacja

```bash
# Zbuduj wszystko (patrz sekcja Budowanie), potem:
./scripts/install.sh                      # instaluje do /usr/local/bin
PREFIX=/opt/zenit ./scripts/install.sh        # inny prefiks
DESTDIR=/mnt/root ./scripts/install.sh          # instalacja do obrazu (budowa pakietów dystrybucji)

# Deinstalacja:
./scripts/uninstall.sh

# Albo przez nimble/janet:
nimble install
janet build.janet -- install
```

`install.sh` **tylko kopiuje binaria** — nie rejestruje pakietu w
dpkg/rpm/pacman, nie instaluje stron podręcznika (man), i nie konfiguruje
`zsrv` jako faktyczny PID 1. `zboot` **nie jest instalowany tym
skryptem** — trafia na partycję ESP jako `\EFI\BOOT\BOOTX64.EFI`.

## Licencja

Cały projekt jest udostępniony na licencji **Apache License 2.0** — patrz
plik [LICENSE](./LICENSE).

## Status

Projekt jest we wczesnej fazie rozwoju (wszystkie komponenty: `0.1.0`).

- `zesh`: potoki/przekierowania/warunki, job control, aliasy, **`$(...)`**
  (substytucja poleceń) i naprawione rozwijanie `$VAR` poza cudzysłowem.
  Pełna kontrola terminala to TODO.
- `zsrv`: epoll/signalfd, sortowanie topologiczne, cgroups v2, grupy
  procesów (`setsid`), **przełączanie targetu w locie** przez
  `/run/zenit/target`, dwufazowe zamykanie.
- `zboot`: UEFI, higher-half, **mapowanie 4 KiB z uprawnieniami R/W/X
  per-segment ELF** i `EFER.NXE`. Wsparcie BIOS (jako plugin) to kolejny krok.
- `tools/`: 36 narzędzi CLI w Crystalu, w tym `zdb` (symbole ELF +
  deasemblacja), `ar` (prawdziwy ustar + gzip, ochrona przed path
  traversal) i uzupełnione `echo`, `printf`, `free`, `uptime`, `nice`.
- **Testy i instalacja**: `tests/` (Nim), `spec/` (Crystal),
  `scripts/install.sh` + `scripts/uninstall.sh`.

Rejestracja w menedżerach pakietów dystrybucji (dpkg/rpm/pacman) i pełne
pokrycie testami wszystkich 36 narzędzi pozostają świadomie poza zakresem
obecnego etapu.
