# Zenit Linux

**Zenit Linux** to dystrybucja Linuksa budowana od zera, uzależniona od GNU
(libc, toolchain itd.), ale zastępująca klasyczne narzędzia coreutils
własnymi, nowoczesnymi odpowiednikami — a docelowo także własnym
bootloaderem i systemem init. Można podczas instalacji wybrac zamiast ekosystemu zenit base ekosystem gnu.

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
| `echo`    | `echo`        | działa         | wypisywanie tekstu (`-n`, `-e`/`-E`, pełne escape POSIX: `\a\b\f\v\e\c\0NNN\xHH`) |
| `sp`      | `ls`          | szkielet+      | listowanie: kolory, `-R`, `-l` z właścicielem/grupą (`getpwuid`), sortowanie |
| `kp`      | `cp`          | szkielet+      | kopiowanie, `-p` (uprawnienia/mtime), `-P` (linki), `--progress` |
| `wp`      | `cat`         | działa         | wypisywanie zawartości plików (strumieniowo, zweryfikowane) |
| `sz`      | `grep`        | szkielet+      | wyszukiwanie: kontekst `-A/-B/-C`, kolorowanie, `-l/-L`, `-r` rekurencyjne |
| `zn`      | `find`        | szkielet+      | wyszukiwanie: `--exec`, filtry, `-and/-or/-not`, `-L` |
| `lb`      | `wc`          | szkielet+      | liczenie linii/słów/bajtów/znaków (`-m`, UTF-8), najdłuższa linia (`-L`) |
| `wz`      | `ln`          | szkielet+      | dowiązania twarde/symboliczne, czytelny błąd EXDEV |
| `pr`      | `ps`          | szkielet+      | listowanie procesów, `-u`, `--tree`, `--sort=cpu\|mem` |
| `df`      | `df`          | szkielet+      | zajętość dysków, urządzenie/mountpoint z `/proc/mounts` |
| `du`      | `du`          | szkielet+      | zajętość katalogów, wykrywanie hardlinków, `--exclude` |
| `zb`      | `kill`        | szkielet+      | sygnały do procesów, dopasowanie po nazwie (jak `pkill`) |
| `fr`      | `head`/`tail` | szkielet+      | podgląd, `-f` przez inotify (wiele plików naraz) |
| `so`      | `sort`        | szkielet+      | sortowanie, `-m` (scalanie już posortowanych plików) |
| `un`      | `uniq`        | szkielet+      | duplikaty sąsiadujące, `-c`, `--repeated`/`--unique`, `-i` |
| `ar`      | `tar`         | działa (ustar) | archiwizacja, ustar + gzip (`-z`) + GNU @LongLink |
| `gdz`     | `which`       | szkielet+      | lokalizacja polecenia w `$PATH` ("gdzie"), `-a` (wszystkie dopasowania) |
| `en`      | `env`         | szkielet+      | zmienne środowiskowe, `-i` (czyste środowisko)  |
| `id`      | `id`          | szkielet+      | UID/GID z rozwiązywaniem nazw (getpwuid/getgrgid) |
| `kt`      | `whoami`      | szkielet+      | nazwa użytkownika przez getpwuid(getuid()) ("kto") |
| `hn`      | `hostname`    | szkielet+      | odczyt I ustawianie nazwy hosta (`sethostname`) |
| `ro`      | `diff`        | działa         | unified diff (`-u`), algorytm Myersa O(D·(n+m)), hunki z kontekstem |
| `xa`      | `xargs`       | działa         | budowanie/uruchamianie poleceń z stdin, `-I`, `-n`, `-0`, `-P` (równolegle) |
| `zdb`     | `gdb`         | szkielet+      | debugger `ptrace(2)`, symbole ELF (z demanglingiem C++), `attach PID` |
| `pf`      | `printf`      | szkielet+      | `%s`/`%d`/`%f`/`%x`/`%o`, szerokość/precyzja/zero-padding, zapętlenie formatu |
| `wm`      | `free`        | szkielet+      | zajętość RAM/swap z `/proc/meminfo`, `-s/-c` (ciągłe odświeżanie) |
| `up`      | `uptime`      | szkielet+      | czas działania, obciążenie, liczba zalogowanych (`utmp`) |
| `ni`      | `nice`        | szkielet+      | uruchomienie z priorytetem + `renice` (`-p PID`) |
| `zsrvctl` | (nowość)      | działa         | sterowanie `zsrv` (PID 1) przez gniazdo kontrolne: `list`/`status`/`start`/`stop`/`restart`/`isolate`/`reload`/`logs`/`ping` |

37 narzędzi łącznie. „Szkielet” oznacza gotowy interfejs CLI i podstawową
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

> Uwaga: `ro` (`diff`) był poprzednio oparty o tablicę programowania
> dynamicznego O(n·m) do wyznaczania najdłuższego wspólnego podciągu —
> poprawną, ale kosztowną pamięciowo dla dużych plików (n·m rośnie
> kwadratowo niezależnie od tego, jak bardzo pliki są do siebie
> podobne). Zastąpiono ją prawdziwym **algorytmem Myersa**
> (`tools/ro/src/myers_diff.cr`, O(D·(n+m)), gdzie D to liczba
> faktycznych różnic) — dla dwóch dużych, w większości identycznych
> plików (typowy przypadek użycia `diff`) to zysk o rzędy wielkości:
> zmierzone ręcznie na dwóch plikach po 50 000 linii z 20 rozproszonymi
> różnicami — 45 MB RAM i 0.04 s, podczas gdy stara tablica DP
> potrzebowałaby ok. 10 GB (50000×50000×4 B) na samą macierz. Poprawność
> zweryfikowana: 500 losowych par plików, których łaty wygenerowane
> przez `ro` zostały odtworzone narzędziem `patch` i porównane bajt w
> bajt z oczekiwanym wynikiem (wszystkie się zgodziły); dodatkowo przy
> okazji poprawiono format nagłówka `@@ -0,0 ...@@` dla insercji/usunięć
> na granicy pustego pliku (niezgodny wcześniej z konwencją GNU diff) i
> błąd kompilacji w `gdz` (`File::Info.executable?` nie istnieje w
> aktualnym Crystalu — poprawne wywołanie to `File.executable?`).

> Uwaga: `xa` (`xargs`) miał dwa realne braki. Po pierwsze, uruchamianie
> równoległe (`-P NUM`) było jawnym TODO — dodano przez pulę fiberów
> Crystala z semaforem (zbuforowany `Channel(Nil)` o pojemności `NUM`
> ogranicza liczbę procesów w locie), zmierzone empirycznie: 8 zadań po
> 0.5 s trwało ~4.0 s sekwencyjnie (`-P 1`, domyślnie), ~1.0 s przy
> `-P 4` i ~0.5 s przy `-P 0` (bez limitu) — dokładnie zgodnie z
> oczekiwaniem. Po drugie, i poważniejsze: `xa` w ogóle nie potrafiło
> przekazać poleceniu docelowemu JEGO WŁASNYCH flag (np. `xa echo -n x`
> albo `xa sh -c '...'` kończyło się błędem `Invalid option: -c`), bo
> `OptionParser` Crystala domyślnie "przetasowuje" argumenty i próbuje
> interpretować KAŻDY token zaczynający się od `-` jako opcję `xa`,
> nawet po nazwie polecenia — co łamało podstawowe zastosowanie xargs.
> Naprawiono ręcznym wstępnym skanowaniem `ARGV`, które zatrzymuje się
> na pierwszym "gołym" argumencie (albo separatorze `--`) i przekazuje
> WSZYSTKO od tego miejsca bez zmian jako polecenie + jego argumenty,
> z pominięciem `OptionParser` całkowicie dla tej części — dokładnie tak,
> jak robi to GNU xargs.


## Komponenty systemowe (Nim) — podzielone na moduły

### `zboot` — bootloader (UEFI + BIOS, higher-half, uprawnienia per-segment)

Bootloader ma **dwa niezależne backendy firmware**, każdy jako osobna
binarka: UEFI (Nim, `bootloader/zboot.nim`, opisany formalnym interfejsem
`BootBackend` w `bootloader/zbootpkg/backend.nim`) i BIOS (NASM,
`bootloader/bios/`, MBR + drugi etap). Oba realizują tę samą umowę
funkcjonalną (mapa pamięci, wczytanie jądra ELF64, higher-half + per-segment
R/W/X, przekazanie `BootInfo` i skok do jądra), ale BIOS musi to zrobić
ręcznie w asemblerze — startuje w 16-bitowym trybie rzeczywistym, do
którego nie da się skompilować kodu Nim, więc kod sam przeprowadza
przejście real mode → protected mode → long mode, zanim cokolwiek
"wysokopoziomowego" może się wykonać (szczegóły w komentarzach na górze
`bootloader/bios/stage1.asm` i `stage2.asm`).

```
bootloader/
├── zboot.nim                # punkt wejścia UEFI (efiMain) — spina moduły
├── zbootpkg/
│   ├── uefi_types.nim         # struktury UEFI (System Table, Boot Services, protokoły plików)
│   ├── console.nim              # wypisywanie tekstu (ConOut), efiPrintHex/efiPrintUInt (bez alokacji), panic() z hlt po ExitBootServices
│   ├── memory.nim                 # GetMemoryMap z pełną pętlą ponawiania (BUFFER_TOO_SMALL)
│   ├── filesystem.nim               # odczyt obrazu jądra z prawdziwego wolumin startowego (LoadedImageProtocol), GetInfo -> dokładny rozmiar bufora
│   ├── elf.nim                        # parsowanie ELF64 + kopiowanie segmentów (array[16], bez seq) do fizycznej bazy
│   ├── graphics.nim                     # Graphics Output Protocol — framebuffer dla jądra, wybór najwyższej rozdzielczości
│   ├── paging.nim                         # WŁASNE tablice stron: identity map (2 MiB) + jądro (4 KiB, per-segment R/W/X) + guard page
│   ├── handoff.nim                          # BootInfo (layout zgodny bajt-w-bajt z BIOS-em), dedykowany stos jądra (z guard page'em) i skok do jądra
│   └── backend.nim                            # formalny interfejs BootBackend (dokumentuje też relację do backendu BIOS)
└── bios/                     # backend BIOS — NASM, osobna binarka MBR/VBR (NIE Nim, patrz backend.nim)
    ├── stage1.asm              # MBR (512 B): sprawdza rozszerzenia INT13h LBA, wczytuje stage2, skacze dalej
    ├── stage2.asm                # real mode -> protected mode -> long mode: E820, A20, VBE, wczytanie ELF64 jądra
    │                             #   z dysku (surowe LBA, patrz scripts/make-bios-image.py), WŁASNE tablice stron
    │                             #   (identity 2 MiB + jądro per-segment 4 KiB, tak jak UEFI), BootInfo, skok do jądra
    └── test/                    # minimalne testowe jądro higher-half (NIE Zenit Linux) do weryfikacji w QEMU
        ├── testkernel.asm         # sprawdza BootInfo i realne uprawnienia stron (PTE) nadane przez stage2
        ├── linker.ld               # wymusza 2 segmenty PT_LOAD (R+X / R+W) — test faktycznie coś sprawdza
        └── README.md                # jak zbudować i uruchomić test w QEMU (patrz też sekcja "Budowanie" niżej)
```

**Tryb graficzny VBE po stronie BIOS** (nowość): `stage2.asm::detect_vbe`
robi w 16-bit real mode dokładnie to, co `graphics.selectHighestResolutionMode`
robi po stronie UEFI — odpytuje wszystkie dostępne tryby (`INT 10h/AX=4F00h/4F01h`),
wybiera ten o największej rozdzielczości z dostępnym liniowym
framebufferem i ustawia go (`AX=4F02h`). Best-effort: brak VBE albo brak
pasującego trybu zostawia `BootInfo.fbBase = 0`, tak jak
`FramebufferInfo(present: false)` po UEFI. **Przetestowane rzeczywiście
w QEMU** (zainstalowany `nasm`+`qemu-system-x86_64`, nie tylko
zasemblowane) w trzech konfiguracjach (`-vga std`, domyślne urządzenie,
`-vga none`) — wszystkie kończą się `WYNIK = PASS` w `bootloader/bios/test/`.
To rzeczywiste uruchomienie ujawniło i pozwoliło naprawić realny błąd
(`mul ecx` kasujące `DX`, w którym siedział numer sprawdzanego trybu —
przez co żaden tryb nigdy nie był faktycznie wybierany, mimo poprawnego
przejścia przez wszystkie filtry, i mimo że `nasm` asemblowało kod bez
żadnego błędu). Pełny opis w `bootloader/bios/test/README.md`, sekcja
"Wykrywanie trybu graficznego VBE".

**Weryfikacja linii A20** (nowość): `stage2.asm::check_a20` sprawdza po
`enable_a20`, czy A20 FAKTYCZNIE działa (klasyczny test "zawijania"
adresu `0x000500`/`0x100500`), zamiast ślepo ufać kodom powrotu BIOS-u.
Jądro ładuje się pod `KERNEL_PHYS_BASE=0x200000` (powyżej granicy
1 MiB), więc bez A20 kopiowanie segmentów ELF cicho zawinęłoby się i
nadpisało pamięć w złym miejscu. Przy wykrytym błędzie `entry16`
zatrzymuje się z jasnym komunikatem zamiast kontynuować w stronę takiej
korupcji. Przetestowane w QEMU w obu kierunkach (A20 włączona i
świadomie wymuszona jako wyłączona przez bezpośrednią manipulację portem
`0x92`) — opis w `bootloader/bios/test/README.md`, sekcja "Weryfikacja
linii A20".

## Błąd fundamentalny znaleziony i naprawiony: backend UEFI nigdy wcześniej nie działał

Zainstalowany `nim`+`gcc-mingw-w64-x86-64`+`ovmf`+`qemu-system-x86_64`
(wszystkie przez `apt`) pozwolił po raz pierwszy **skompilować I
URUCHOMIĆ** backend UEFI zamiast tylko czytać jego kod. Efekt: **cały
backend UEFI nigdy wcześniej nie działał, w żadnej wersji tego
repozytorium** — nie tylko w zmianach z tej sesji. Dwa niezależne,
fundamentalne błędy uniemożliwiały mu dotarcie dalej niż do banera
powitalnego:

1. **Mutacja/konkatenacja Nim `string` i `seq` crashuje twardym triple
   faultem** w tym freestanding środowisku (`--os:any -d:useMalloc
   -nostdlib`), ZANIM w ogóle dotrze do własnego alokatora
   (`zbootpkg/allocator` — `malloc()` nigdy nie było wołane). Dotyczyło
   to `efiPrintHex` (mutacja `buf[i] = ...` na `var string`), każdego
   użycia `&`/`$` do budowania komunikatów diagnostycznych w `zboot.nim`/
   `elf.nim`/`filesystem.nim`/`graphics.nim`, `filesystem.asciiToUtf16Path`
   (`newSeq[uint16]`) oraz `elf.ParsedKernel.segments` (`seq[LoadSegment]`
   z `.add()`). Naprawione przez: nowy `console.efiPrintUInt` i
   przepisany `efiPrintHex`, oba pracujące WYŁĄCZNIE na `array` o stałym
   rozmiarze (ten sam wzorzec co już działający `efiPrint`); rozbicie
   wszystkich `&`/`$` na sekwencje wywołań `efiPrint`/`efiPrintUInt`;
   `asciiToUtf16Path` przepisane na stały `array[64, uint16]`; oraz
   `ParsedKernel.segments` zamienione z `seq[LoadSegment]` na
   `array[16, LoadSegment]` + `segmentCount: int` (16 to spory zapas —
   realne jądra mają 3-6 segmentów PT_LOAD), z odpowiednią aktualizacją
   `zbootpkg/paging.buildPageTables`/`mapKernelSegments`.
2. **`BootInfo` (Nim, `zbootpkg/handoff`) miało INNY layout niż to, co
   ręcznie zapisuje `bootloader/bios/stage2.asm`** — brakowało pól
   `firmwareKind` (offset `0x45`) i `memoryMapEntryCount` (offset `0x48`),
   które backend BIOS zawsze zapisywał. Jądro odczytujące te pola po
   starcie z UEFI czytałoby przypadkowe bajty pamięci ZA końcem struktury
   (`sizeof(BootInfo)` wynosiło dokładnie `0x48` — offset `0x48` był więc
   już poza nią) zamiast rzeczywistych wartości. Naprawione dodaniem
   obu pól do `BootInfo` w kolejności/rozmiarach dającą DOKŁADNIE te same
   offsety co w BIOS-ie (zweryfikowane przez `sizeof`), i ich
   wypełnieniem w `buildBootInfo` (`firmwareKind = 0`, `memoryMapEntryCount
   = memoryMapSize div memoryMapDescSize`).

**W pełni zweryfikowane w QEMU+OVMF** (obraz ESP z `EFI/BOOT/BOOTX64.EFI`
+ `ZENIT/KERNEL.ELF`, ten sam `testkernel.elf` co w teście BIOS-owym):
pełna ścieżka rozruchu — odczyt jądra z ESP przez
`EFI_LOADED_IMAGE_PROTOCOL`, parsowanie ELF64, budowa tablic stron z
guard page'em, wybór trybu graficznego, `ExitBootServices`, skok do
jądra — kończy się `WYNIK = PASS` z poprawnymi wartościami wszystkich pól
`BootInfo` (`firmwareKind=0x00`, sensowny `e820EntryCount`, poprawne PTE
dla `.text`/`.data`). Backend BIOS przetestowany ponownie na tym samym
`testkernel.elf` żeby potwierdzić brak regresji — również `WYNIK = PASS`,
z `firmwareKind=0x01` i tymi samymi, spójnymi wartościami pozostałych pól.

**Higher-half + uprawnienia per-segment**: `zbootpkg/elf` (UEFI) i
`stage2.asm::entry64` (BIOS) wyznaczają rozpiętość segmentów PT_LOAD i
kopiują je pod fizyczną bazę zachowując ich względne odległości z
linkowania (UEFI alokuje tę bazę dynamicznie przez `AllocatePages`; BIOS na
tym etapie używa stałej bazy `0x200000` — prostsze, ale mniej elastyczne,
patrz TODO w `stage2.asm`). Obie ścieżki budują WŁASNE tablice stron
(PML4/PDPT/PD/PT): identity mapping niskiej pamięci stronami 2 MiB oraz
**każdy segment jądra mapowany OSOBNO stronami 4 KiB** z uprawnieniami
odczytanymi z `p_flags` ELF — sekcja `.text` dostaje R+X
(bez W), `.data`/`.bss` dostają R+W (bez X), zamiast jednego zbyt
szerokiego mapowania R+W+X dla całego jądra naraz. Przed użyciem bitu NX
włączane jest `EFER.NXE` (inaczej ustawienie NX przy wyłączonym NXE
powoduje `#GP` zamiast zablokować wykonywanie). Przełączenie `CR3`

następuje dopiero **po** `ExitBootServices` (przed tym firmware polega na
własnych tablicach stron).

**Identity mapping wyliczany dynamicznie** (nowość): `zboot.computeIdentityMapGiB`
odczytuje najwyższy adres fizyczny zgłoszony przez firmware w mapie pamięci
UEFI (`zbootpkg/memory.maxPhysicalAddress`, nowa funkcja) i zaokrągla go w
górę do pełnych GiB, zamiast zakładać sztywne 4 GiB niezależnie od
rzeczywistej ilości RAM-u — z dolnym progiem 4 GiB (zapas na bufory zboot
na maszynach z mało pamięcią) i górnym 512 GiB (zabezpieczenie przed
wadliwym firmware zgłaszającym fikcyjny region bliski szczytowi
przestrzeni adresowej).

**Wybór najwyższej rozdzielczości GOP** (nowość): `graphics.selectHighestResolutionMode`
iteruje WSZYSTKIE tryby zgłoszone przez Graphics Output Protocol
(`QueryMode` dla `i in 0 ..< maxMode`) i przełącza się przez `SetMode` na
ten o największej liczbie pikseli, zamiast akceptować tryb ustawiony
domyślnie przez firmware (często niska rozdzielczość "bezpieczna" dla
ekranów awaryjnych). Best-effort: błąd `QueryMode`/`SetMode` dla
konkretnego trybu jest pomijany, a brak jakiejkolwiek poprawy nie jest
traktowany jako błąd krytyczny — jądro i tak dostaje `FramebufferInfo`
odzwierciedlający to, co faktycznie jest aktywne w momencie odczytu.

**Właściwy wolumin startowy przez `EFI_LOADED_IMAGE_PROTOCOL`** (nowość):
`filesystem.locateEspFileSystem` odczytuje `DeviceHandle` z
`EFI_LOADED_IMAGE_PROTOCOL` powiązanego z WŁASNYM `imageHandle` zboot i
dopiero na nim wywołuje `HandleProtocol` dla Simple File System — czyli
zawsze trafia w wolumin, z którego zboot faktycznie wystartowało,
niezależnie od tego, ile wolumenów z systemem plików ma dana maszyna.
Poprzedni, uproszczony `LocateProtocol` (poprawny tylko przy DOKŁADNIE
jednym woluminie FS w systemie) pozostaje jako awaryjny fallback, gdyby
firmware nie eksponował poprawnie `EFI_LOADED_IMAGE_PROTOCOL`.

**Guard page pod stosem jądra** (nowość): stos przekazywany jądru w
`BootInfo` nie jest już statycznym buforem w BSS zboot — `handoff.allocKernelStack`
alokuje go osobno przez `AllocatePages` (16 stron = 64 KiB, tak jak
poprzednio) z JEDNĄ dodatkową stroną PONIŻEJ, którą `paging.punchGuardPage`
oznacza jako `not present` w tablicach stron. Ponieważ ta strona leży w
obszarze objętym gruboziarnistym identity-mappingiem 2 MiB
(`mapRegion2M`), `punchGuardPage` najpierw "demuje" odpowiedni wpis PD ze
strony 2 MiB na tablicę 512 wpisów po 4 KiB (zachowując uprawnienia
oryginalnej strony dla wszystkich podstron OPRÓCZ tej jednej), a dopiero
potem czyści wpis dla strony strażniczej. Efekt: przepełnienie stosu
podczas bardzo wczesnego rozruchu jądra (zanim jądro zdąży ustawić
własny, docelowy stos) kończy się natychmiastowym `#PF` zamiast cichej
korupcji sąsiedniej pamięci.

**Pełna klasyfikacja typów pamięci przy liczeniu dostępnego RAM-u**
(nowość): `memory.totalUsableBytes` liczy teraz WSZYSTKIE typy regionów,
które firmware oddaje systemowi po `ExitBootServices()` — nie tylko
`EfiConventionalMemory`, ale też `EfiLoaderCode`/`EfiLoaderData`
(sam obraz zboot) i `EfiBootServicesCode`/`EfiBootServicesData` (kod/dane
samych boot services) — zamiast wcześniej zaniżonego przybliżenia liczącego
tylko jeden typ. `EfiRuntimeServices*`, ACPI NVS i MMIO celowo NIE są
liczone: te firmware zachowuje dla siebie albo w ogóle nie są pamięcią
operacyjną.

**`hlt` w pętli `panic()` PO ExitBootServices** (nowość): `console.panic()`
sprawdza teraz nową flagę `gBootServicesExited` (ustawianą przez
`zboot.nim` zaraz po udanym `ExitBootServices()`) i dopiero wtedy wchodzi
w pętlę `hlt` zamiast czystego busy-spinu — przed tym momentem
zatrzymanie CPU nadal należy do firmware, więc pętla zostaje bez zmian.
`hlt` zatrzymuje rdzeń do najbliższego przerwania zamiast wypalać go w
nieskończonej pustej pętli — standardowy wzorzec pętli bezczynności
jądra, zastosowany tu też w ścieżce awaryjnej bootloadera.

### `zsrv` — system init (PID 1)

```
init-system/
├── zsrv.nim                 # punkt wejścia — spina moduły
└── zsrvpkg/
    ├── types.nim               # ServiceDef, ServiceRuntime (stan + stoppedByAdmin), ResourceLimits, Target
    ├── state.nim                 # globalny stan: tabela usług, aktywny target
    ├── logger.nim                  # logowanie z rotacją pliku
    ├── parser.nim                    # parsowanie *.zsrv (User=, MemoryMax=, CPUQuota=, StopSec=) + reloadServices
    ├── depgraph.nim                     # sortowanie topologiczne zależności (After=), algorytm Kahna
    ├── cgroups.nim                        # limity zasobów przez cgroups v2 + subtree_control
    ├── supervisor.nim                       # start/stop/restart, dropPrivileges, setsid, grupy procesów
    ├── target.nim                              # target startowy + przełączanie w locie (/run/zenit/target)
    ├── control.nim                               # gniazdo kontrolne AF_UNIX dla zsrvctl (/run/zenit/control.sock)
    └── eventloop.nim                             # pętla epoll + signalfd + gniazdo kontrolne
```

**Grupy procesów i przełączanie targetu w locie**: każda usługa
dostaje własne PGID przez `setsid()` w procesie potomnym — dzięki temu
`SIGTERM`/`SIGKILL` trafiają do **całej grupy procesów** usługi
(`kill(-pid, sygnał)`), nie tylko do bezpośredniego procesu potomnego, więc
dzieci uruchomione przez usługę też są poprawnie zatrzymywane. Target da
się przełączyć w locie na dwa sposoby: ręcznie, jak dotychczas
(`echo rescue > /run/zenit/target && kill -HUP 1`), albo wygodnie przez
`zsrvctl isolate rescue` (patrz niżej) — `zsrv` w obu przypadkach
**zatrzyma usługi spoza nowego targetu** (wcześniej `applyTarget` tylko
dokładał usługi, nigdy nie zatrzymywał).

**Gniazdo kontrolne i `zsrvctl`** (nowość): `zsrvpkg/control` otwiera
gniazdo AF_UNIX/SOCK_STREAM w `/run/zenit/control.sock`, dopięte do tej
samej pętli `epoll` co signalfd (`zsrvpkg/eventloop`) — bez dodatkowego
wątku ani pollingu. Protokół jest celowo trywialny: jedna linia tekstu
polecenia, jedna lub więcej linii odpowiedzi zakończonych `OK`/`ERR ...`,
połączenie zamykane przez `zsrv` zaraz potem. Obsługiwane polecenia:
`list`, `status <nazwa>`, `start <nazwa>`, `stop <nazwa>`,
`restart <nazwa>`, `isolate <target>`, `reload`, `logs <nazwa> [N]`,
`ping`. Nowe narzędzie CLI `zsrvctl` (`tools/zsrvctl`, Crystal) łączy się
z gniazdem i wypisuje odpowiedź — to jest dokładnie to narzędzie, które
wcześniejsza wersja tego README zapowiadała jako "przyszłe". Best-effort:
brak `/run/zenit` albo nieudany `bind()`/`listen()` nie są traktowane
jako błąd krytyczny — `zsrv` działa dalej wyłącznie na sygnałach, tak jak
wcześniej.

**`zsrvctl reload`** (nowość): `parser.reloadServices` wczytuje ponownie
`/etc/zenit/services`, ale — w odróżnieniu od `loadServices` używanego
przy starcie — NIE czyści tabeli `services` na zero. Zamiast tego: nowe
pliki `.zsrv` dodają nowe usługi (stan początkowy `stopped`), zmienione
pliki podmieniają TYLKO `def` istniejącej usługi (ExecStart/limity/itd.),
zachowując jej pid/stan/licznik restartów w całości, a usunięte pliki
kasują wpis z tabeli TYLKO jeśli usługa jest już zatrzymana — wciąż
działającą usługę reload zostawia w tabeli (z ostrzeżeniem w logu), żeby
nie zamienić jej w nienadzorowaną sierotę. Po reloadzie wywoływane jest
`applyTarget(currentTarget)`, więc nowo dodane usługi z pasującym
`WantedBy=` startują od razu, bez oddzielnego `start`.

**`zsrvctl logs`** (nowość): `logs <nazwa> [N]` zwraca (maksymalnie) `N`
ostatnich linii pliku `/var/log/zenit/<nazwa>.log` (domyślnie 20, maks.
500) — `zsrvpkg/control.tailLines` czyta tylko ostatnie 256 KiB pliku
zamiast całości, bo logi usług (w odróżnieniu od `/var/log/zsrv.log`,
patrz `zsrvpkg/logger`) nie mają dziś rotacji i mogłyby urosnąć dowolnie
duże. Pozwala zerknąć w log usługi bez ręcznego SSH/wchodzenia do
`/var/log/zenit/`.

**Trzy realne błędy znalezione i naprawione przez rzeczywisty test
end-to-end** (zainstalowane `nim`+`crystal` przez apt, `nimble buildInit`
+ `nimble buildShell`, uruchomiony prawdziwy `zsrv` jako zwykły proces i
sterowany przez skompilowany `zsrvctl`) — żaden z nich nie był widoczny
przy samej kompilacji ani przy testach jednostkowych, bo wszystkie trzy
dotyczą interakcji w czasie działania (timing, cykl życia procesów),
której testy jednostkowe nie odtwarzają:

1. **Gniazdo nasłuchujące nie było nieblokujące.** Pętla "przyjmij
   wszystkie oczekujące połączenia" w `zsrvpkg/eventloop` blokowała się na
   DRUGIM `accept()`, zamrażając CAŁĄ pętlę zdarzeń zsrv na zawsze zaraz
   po obsłużeniu pierwszego w historii połączenia od `zsrvctl`. Naprawione
   przez `O_NONBLOCK` na gnieździe nasłuchującym (`setNonBlocking` w
   `zsrvpkg/control`).
2. **Wyścig w protokole tekstowym gniazda kontrolnego.** Klient (Crystal
   `Socket#puts`) wysyła treść polecenia i kończący znak nowej linii jako
   DWA OSOBNE zapisy. `handleControlConnection` robiło tylko JEDNO
   `read()` — odbierało samo `"ping"` (bez `\n`), od razu odpowiadało i
   zamykało gniazdo, a drugi zapis klienta trafiał w już zamknięte
   gniazdo, dając `EPIPE`/`SIGPIPE` po stronie klienta mimo że polecenie
   de facto się wykonało. Naprawione przez pętlę odczytu czekającą na
   `\n` albo EOF.
3. **`zsrvctl stop` nie działało dłużej niż jeden obrót pętli zdarzeń.**
   `applyTarget` (wołane na KAŻDYM obrocie pętli, żeby dokładać usługi
   czekające na zależność) natychmiast z powrotem uruchamiało KAŻDĄ
   usługę zatrzymaną przez `stop`, jeśli nadal należała do aktywnego
   targetu — bo nic nie odróżniało "zatrzymana jawnie" od "jeszcze nie
   wystartowana". Naprawione nowym polem `stoppedByAdmin` w
   `ServiceRuntime` (types.nim) i parametrem `applyTarget(target, force)`:
   wywołania cykliczne (`force=false`, domyślne) pomijają usługi zatrzymane
   jawnie, a wywołania `isolate`/`SIGHUP`/start systemu (`force=true`)
   startują wszystko zgodnie z docelowym targetem niezależnie od historii
   — `startService` i tak czyści tę flagę przy każdym starcie. Przy okazji
   naprawiony powiązany błąd: `stopService`/`handleExitedChild` nie
   rozróżniały zamierzonego zatrzymania (`ssStopping`) od crasha,
   pokazując `state=failed` zamiast `state=stopped` po zwykłym `stop` — i
   nie czyściły `stopDeadline` po czystym zatrzymaniu, co po `StopSec=`
   sekundach zamieniało `epoll_wait` w busy-loop z timeoutem 0, zżerający
   cały rdzeń CPU NA ZAWSZE po pierwszym kiedykolwiek zatrzymaniu
   jakiejkolwiek usługi.

Przetestowane ręcznie krok po kroku: `stop` → stan zostaje `stopped`
(nie `failed`) i NIE wraca samo z siebie przez kolejne sekundy; `start`
jawnie je wskrzesza; `isolate rescue` → `isolate multi-user` poprawnie
odtwarza usługę mimo wcześniejszego `stop`; zużycie CPU pozostaje na 0%
przez 10+ sekund po `StopSec=5` — żadnego busy-loopa.

**Format `.zsrv` rozszerzony**: nagłówki sekcji w stylu systemd
(`[Unit]`/`[Service]`, czysto kosmetyczne, po cichu pomijane — dyrektywy
działają identycznie niezależnie od sekcji), komentarze na końcu linii z
dyrektywą (`Key=Value  # komentarz`, z poszanowaniem cudzysłowów — `#`
bez poprzedzającej spacji w wartości NIE jest traktowany jako komentarz),
oraz poprawna tokenizacja `ExecStart=` w stylu powłoki
(`parser.tokenizeExecLine`) — argumenty w cudzysłowach mogą teraz
zawierać spacje (`ExecStart=/bin/foo --name "moja usluga"` daje argument
`moja usluga`, nie dwa osobne argumenty jak przy poprzednim naiwnym
`splitWhitespace()`). Parser `/proc/cmdline` (`target.parseCmdlineTokens`)
też respektuje cudzysłowy i skanuje WSZYSTKIE argumenty programu (nie
tylko pierwszy) w poszukiwaniu `--target=`.

**`Environment=` w plikach `.zsrv`** (nowość): usługi mogą teraz definiować
dodatkowe zmienne środowiskowe swojego procesu — `Environment=KLUCZ=WARTOSC`,
z możliwością wielu par na jednej linii (`Environment=FOO=1 BAR=2`),
wielokrotnego wystąpienia dyrektywy (wartości się KUMULUJĄ, tak jak w
systemd — ostatnie wystąpienie tego samego klucza wygrywa) i wartości w
cudzysłowie zawierającej spacje (`Environment=GREETING="hello world"`,
przez ponowne użycie `parser.tokenizeExecLine` zamiast pisania osobnego
parsera). Zastosowanie następuje w `supervisor.applyServiceEnvironment`,
W PROCESIE POTOMNYM po `fork()` i przed `execvp()`, przez `putEnv` —
proces dziedziczy resztę środowiska PID 1 normalnie, to tylko dokłada
wybrane klucze.

**Rozstrzygnięta niejasność projektowa**: brakująca usługa w `After=`
(literówka albo usunięty plik `.zsrv`) NIE blokuje już rozruchu w
nieskończoność ani nie jest cicho ignorowana — loguje się jako WYRAŹNE
ostrzeżenie (raz na parę usługa/zależność) i jest traktowana jako
spełniona, żeby reszta systemu i tak wystartowała (analogicznie do tego,
jak systemd traktuje nierozwiązane `After=` łagodniej niż `Requires=`).

Funkcje: cgroups v2 z `subtree_control`, logi per-usługa w
`/var/log/zenit/<usługa>.log`, uruchamianie na innym użytkowniku
(`User=` → `setgid`+`setuid`), dwufazowe zamykanie (`SIGTERM` →
`SIGKILL` po `StopSec=`), pętla zdarzeń na `epoll`+`signalfd`.

**Testowane** w `tests/test_depgraph.nim` (sortowanie topologiczne, w tym
cykle zależności i zależności spoza aktywnego zestawu) i
`tests/test_service_parser.nim` (17 przypadków: sekcje, komentarze,
cudzysłowy w `ExecStart`, sufiksy rozmiaru, itd.).

### `zesh` — powłoka

```
zesh/
├── zesh.nim                 # punkt wejścia: REPL, `-c POLECENIE`, wykonanie pliku skryptu
└── zeshpkg/
    ├── state.nim               # zmienne, aliasy, historia, ostatni kod wyjścia, $0/scriptArgs
    ├── vars.nim                  # $NAME/${NAME}/$?/$(polecenie)/$((wyrażenie)), lokalne vs eksportowane
    ├── cmdhistory.nim              # ~/.zesh_history, odwołania !!/!n/!prefix
    ├── lexer.nim                     # tokenizacja (cudzysłowy, operatory, & w tle, $(...), 2>/2>>/2>&1)
    ├── parser.nim                      # tokeny -> potoki -> instrukcje; splitRawStatements (podział PRZED rozwinięciem zmiennych)
    ├── jobcontrol.nim                    # grupy procesów, tcsetpgrp (prawdziwa kontrola terminala), jobs/fg
    ├── builtins.nim                        # polecenia wbudowane (alias, type, fg, jobs, read, cd -, ...)
    ├── exec.nim                              # fork/setpgid/pipe/dup2/execvp, rekurencyjne rozwijanie aliasów
    ├── interpreter.nim                          # sekwencje `;`, warunki `&&`/`||`, hook $(...)
    └── prompt.nim                                  # budowanie promptu
```

**Tryb `-c` i wykonywanie skryptów** (nowość): `zesh` obsługuje teraz,
oprócz zwykłego REPL-a, dwa tryby nieinteraktywne — `zesh -c 'polecenie' [NAZWA [ARG...]]`
(uruchamia jedno polecenie przez pełny `runLine` i kończy pracę z jego
kodem wyjścia) oraz `zesh SCIEZKA/DO/SKRYPTU [ARG...]` (`zesh.runScriptFile` —
wykonuje plik linia po linii przez ten sam `runLine`, pomijając puste
linie i linie zaczynające się od `#`). Oba tryby pomijają prompt i zapis
do historii poleceń (to nie jest sesja interaktywna); `jobcontrol.initJobControl`
i tak jest wywoływane bezwarunkowo — samo wykrywa brak terminala
(`isatty`) i po cichu nic nie robi, więc potoki i przekierowania w
skryptach działają identycznie jak w trybie interaktywnym.

**Parametry pozycyjne `$0`/`$1`..`$9`/`$@`/`$#`** (nowość): `zeshpkg/vars.expandVars`
rozwija teraz też parametry pozycyjne, czytane z nowych zmiennych
globalnych `zeshpkg/state.scriptName`/`scriptArgs`, ustawianych przez
`zesh.nim` PRZED uruchomieniem polecenia/skryptu — zgodnie z konwencją
`sh -c polecenie nazwa arg1 arg2...` dla `-c` oraz `sh SKRYPT arg1 arg2...`
dla trybu skryptowego. Tylko POJEDYNCZA cyfra po `$` jest rozpoznawana
(`$10` to `$1` + literalne `0`, tak jak w prawdziwym POSIX — dla
dwucyfrowych indeksów trzeba by `${10}`, czego, podobnie jak reszty
`${...}`, nie wspieramy). Odwołanie poza zakres przekazanych argumentów
(np. `$5`, gdy podano tylko dwa) rozwija się do pustego tekstu, tak jak
niezdefiniowana zmienna zwykła. Testowane w `tests/test_vars.nim`.

**Builtin `read`** (nowość): `read var1 var2 ... varN` czyta JEDNĄ linię
ze standardowego wejścia i dzieli ją na słowa — pierwsze N-1 słów trafia
do pierwszych N-1 zmiennych, a WSZYSTKO, co zostanie, do OSTATNIEJ
zmiennej (dokładnie jak w bashu: `read a b` przy wejściu `x y z` daje
`a=x`, `b="y z"`). Bez podanych nazw zmiennych domyślnie używana jest
`REPLY` (konwencja bash). EOF (brak linii do odczytania) zwraca kod 1,
z pustymi wartościami we wszystkich zmiennych — pierwszy realny sposób
na wczytanie danych od użytkownika/z potoku wewnątrz skryptu zesh, obok
argumentów pozycyjnych i zmiennych środowiskowych.

**`cd -` i `$OLDPWD`/`$PWD`** (nowość): każde udane `cd` ustawia teraz
`$OLDPWD` (poprzedni katalog) i `$PWD` (nowy katalog) jako prawdziwe
zmienne środowiskowe (`putEnv`), a `cd -` przełącza z powrotem na
`$OLDPWD` i wypisuje nową ścieżkę — dokładnie zachowanie bashu. Wcześniej
`cd` w ogóle nie dotykało tych zmiennych, więc `$PWD` w skryptach zesh
było zawsze tym, co zostało odziedziczone z procesu-rodzica przy starcie,
niezależnie od kolejnych `cd`.

**Przekierowanie stderr `2>`/`2>>`/`2>&1`** (nowość): obok istniejących
`>`/`>>`/`<`, `lexer.tokenize` rozpoznaje teraz przekierowania
deskryptora 2 — ale TYLKO gdy `2` stoi na POCZĄTKU nowego tokenu (jak w
bashu), więc plik nazwany np. `plik2>x` nie jest mylnie łamany w
środku nazwy. `exec.applyRedirects` stosuje `2>&1` PO ewentualnym
`>plik` w tej samej instrukcji (kolejność przekierowań czytana od lewej
do prawej, tak jak w prawdziwej powłoce POSIX) — `dup2(STDOUT_FILENO, STDERR_FILENO)`
bierze więc deskryptor stdout `taki, jaki jest w danym momencie`, a nie
sprzed przekierowania.

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

**Rozwijanie arytmetyczne `$((...))`**: prosty parser rekurencyjnego
zstępowania (`vars.evalArithmetic`) wspierający liczby dziesiętne i
szesnastkowe (`0x...`), gołe nazwy zmiennych (`$((i+1))`, tak jak w
bashu), nawiasy, jednoargumentowe `+ - !`, dwuargumentowe `* / % + -`,
porównania `== != < <= > >=` (dające `1`/`0`) i logiczne `&& ||`. Celowo
bez operatorów bitowych ani przypisań wewnątrz wyrażenia — pokrywa to
zdecydowaną większość realnego użycia (liczniki pętli, warunki) przy
znacznie prostszym i łatwiejszym do zweryfikowania parserze.

**Naprawiony błąd (rozwijanie `$?`/`$(...)` per instrukcja)**: `runLine`
wcześniej tokenizował (i tym samym rozwijał WSZYSTKIE zmienne) **całą
linię za jednym razem**, zanim jakakolwiek jej instrukcja się wykonała —
więc `false; echo $?` pokazywało kod wyjścia sprzed całej linii, nie
kod `false`, bo `$?` był rozwijany, zanim `false` w ogóle ruszyło.
Naprawione przez `parser.splitRawStatements`: **surowy** tekst linii jest
dzielony na instrukcje przy `;`/`&&`/`||` (z poszanowaniem cudzysłowów i
`$(...)`) na poziomie znaków, *przed* jakimkolwiek rozwinięciem — dopiero
potem `interpreter.runLine` tokenizuje (i rozwija) każdą instrukcję
OSOBNO, bezpośrednio przed jej wykonaniem.

**Prawdziwa kontrola terminala**: `jobcontrol.initJobControl()` (wywoływane
raz, na starcie) czyni `zesh` liderem własnej grupy procesów i przejmuje
terminal (klasyczna sekwencja z GNU libc manual, "Implementing a Job
Control Shell"), ignorując `SIGTTOU`/`SIGTTIN`/`SIGTSTP`/`SIGINT`/`SIGQUIT`
dla samej powłoki. Każdy potok dostaje WŁASNĄ grupę procesów
(`exec.forkPipeline`, `setpgid` w dziecku ORAZ w rodzicu — klasyczny
wyścig z tego samego podręcznika, zamykany wywołaniem z obu stron), a
terminal jest oddawany tej grupie na czas jej działania pierwszoplanowego
(`giveTerminalTo`/`reclaimTerminal`, `tcsetpgrp`) — dzięki temu Ctrl+C
faktycznie trafia do uruchomionego polecenia, a nie do `zesh`. Procesy
potomne dostają z powrotem DOMYŚLNĄ obsługę tych sygnałów tuż przed
`execvp` (`resetChildSignals`) — inaczej odziedziczyłyby ignorowanie po
rodzicu. Kod wyjścia procesu zabitego sygnałem jest teraz raportowany
jako `128+sygnał` (konwencja uniksowa; poprzednio `$?` błędnie pokazywał
`0`, swoją wartość początkową, bo aktualizowany był tylko przy
`WIFEXITED`).

**Rozwijanie historii `!prefix`** (nowość): obok już istniejącego `!!`
(ostatnie polecenie) i `!n` (polecenie numer n), `cmdhistory.expandHistoryRefs`
obsługuje teraz `!prefix` -- rozwija się do NAJNOWSZEGO wpisu w historii
zaczynającego się od `prefix`, szukanego wstecz (jak w bashu). Sygnatura
funkcji zwraca teraz parę `(rozwinięta_linia, powiodło_się)` zamiast samego
tekstu: nieznany numer zdarzenia albo brak dopasowania prefiksu kończy się
komunikatem błędu na stderr i `zesh.nim` **ani nie uruchamia, ani nie
dopisuje takiej linii do historii** (wcześniej nieudane `!!` na pustej
historii cicho zwracało pusty tekst, który i tak trafiał do historii i
uruchamiał się jako pusta linia).

**Rekurencyjne rozwijanie aliasów**: `exec.resolveAlias` podmienia
pierwsze słowo w PĘTLI (alias może rozwijać się do innego aliasu), z
zestawem już-podstawionych nazw chroniącym przed nieskończoną pętlą, gdy
alias (pośrednio) odwołuje się sam do siebie.

> Uwaga historyczna: moduły `history.nim` i `jobs.nim` (analogicznie
> `zsrvpkg/log.nim`) zostały przemianowane na `cmdhistory.nim`,
> `jobcontrol.nim` i `logger.nim` — Nim traktuje moduł i zmienną/proc o
> identycznej nazwie jako kolizję, co blokowało kompilację. Osierocona
> kopia pod starą nazwą (`zeshpkg/history.nim`, dokładny duplikat
> `cmdhistory.nim`, nigdzie nieimportowana) została usunięta.

**Testowane** w `tests/test_lexer.nim` (w tym test na `$(...)` ze spacją
w środku, oraz na przekierowania `2>`/`2>>`/`2>&1` i na to, że `2` w
środku nazwy pliku nie jest z nimi mylone), `tests/test_parser.nim` i
`tests/test_vars.nim` (parametry pozycyjne `$0`/`$1`../`$@`/`$#`),
oraz ręcznie na prawdziwym PTY
(`pty.fork()` + wysyłka Ctrl+C) — potwierdzone, że sygnał trafia do
pierwszoplanowego procesu, a nie do `zesh`. Cykl Ctrl+Z → `jobs` → `bg
%N` → `fg %N` → ponowny Ctrl+Z również zweryfikowany end-to-end na
prawdziwym PTY: zadanie poprawnie przechodzi Running → Stopped →
(przez `bg`) Running → (przez `fg` + Ctrl+Z) z powrotem Stopped, bez
utraty numeru zadania ani zombie procesów.

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
├── shard.yml                  # definicje WSZYSTKICH narzędzi Crystal (37 narzędzi)
├── zenit_base.nimble           # definicje komponentów Nim (zesh, zboot, zsrv) + zadania test/install/buildBootloaderBios
├── build.janet                  # orkiestrator budowy całości (+ `-- test`, `-- install`)
├── scripts/
│   ├── install.sh                # kopiuje zbudowane binaria do PREFIX/bin (domyślnie /usr/local/bin)
│   ├── uninstall.sh                # usuwa je z powrotem
│   └── make-bios-image.py           # buduje surowy obraz dysku (stage1+stage2+jądro) do testów QEMU backendu BIOS
├── packaging/
│   ├── zpk.build                     # manifest pakietu (nazwa, wersja, recipe)
│   └── recipe.janet                    # recipe zpk: buduje całość i pakuje do dist/ (BOOTX64.EFI i stage{1,2}.bin -> usr/lib/zenit-base/boot/, reszta -> usr/bin/)
├── tests/                           # testy jednostkowe Nim (uruchamiane przez `nimble test`)
├── spec/                              # testy integracyjne Crystal (uruchamiane przez `crystal spec`)
├── .github/workflows/
│   ├── build-all.yml                   # CI: buduje i pakuje wszystko
│   ├── build-tools.yml                  # CI: narzędzia CLI (Crystal + zesh)
│   ├── build-bootloader.yml              # CI: zboot (UEFI, BOOTX64.EFI, test w QEMU/OVMF)
│   ├── build-bootloader-bios.yml          # CI: zboot (BIOS, stage1+stage2, test w QEMU z testowym jądrem higher-half)
│   ├── build-init-system.yml               # CI: zsrv
│   └── test.yml                             # CI: testy jednostkowe + integracyjne
├── zesh/                                     # powłoka (Nim, moduły w zeshpkg/)
├── bootloader/                                 # bootloader (dwa niezależne backendy, patrz sekcja `zboot` wyżej)
│   ├── zboot.nim                                # backend UEFI (Nim, moduły w zbootpkg/)
│   └── bios/                                      # backend BIOS (NASM, patrz stage1.asm/stage2.asm + test/)
├── init-system/                                  # system init / PID 1 (Nim, moduły w zsrvpkg/)
└── tools/                                          # wszystkie narzędzia CLI (Crystal)
    └── <nazwa>/src/<nazwa>.cr
```

## Budowanie

Wymagania: Nim ≥ 2.0, Crystal ≥ 1.10, Janet, GNU toolchain, a dla
bootloadera dodatkowo krzyżowy toolchain UEFI: `gcc-mingw-w64-x86-64`
(backend UEFI) oraz `nasm` (backend BIOS) — oba opcjonalne/best-effort,
`janet build.janet` próbuje je zainstalować samo (`ensure-mingw`/
`ensure-nasm`), a brak jednego z nich nie przerywa reszty budowy.
Opcjonalnie OVMF + QEMU do testów rozruchu obu backendów.

```bash
# Powłoka zesh (Nim) — kompiluje zesh.nim wraz z modułami z zeshpkg/
nimble buildShell

# System init zsrv (Nim) — kompiluje zsrv.nim wraz z modułami z zsrvpkg/
nimble buildInit

# Bootloader zboot (Nim, UEFI) -> bootloader/BOOTX64.EFI
nimble buildBootloader

# Bootloader zboot (NASM, BIOS) -> bootloader/bios/stage1.bin + stage2.bin
nimble buildBootloaderBios

# Wszystkie komponenty Nim naraz (zesh, zsrv, zboot/UEFI -- BIOS osobno, patrz wyżej)
nimble buildAll

# Narzędzia CLI (Crystal) — 37 narzędzi zdefiniowanych w shard.yml
shards install
shards build --release

# Albo całość naraz, przez orkiestrator:
janet build.janet
```

Nazwa pakietu nimble (`zenit_base`) celowo używa podkreślnika zamiast
myślnika — Nimble odrzuca myślniki w nazwach pakietów jako nieprawidłowe.

Wynikowe binaria trafiają do katalogu `dist/`.

### Testowanie backendu BIOS w QEMU

```bash
nimble buildBootloaderBios
nasm -f elf64 -o /tmp/testkernel.o bootloader/bios/test/testkernel.asm
ld -T bootloader/bios/test/linker.ld -o /tmp/testkernel.elf /tmp/testkernel.o
python3 scripts/make-bios-image.py --kernel /tmp/testkernel.elf --out /tmp/bios-disk.img
qemu-system-x86_64 -machine pc -m 256 -drive format=raw,file=/tmp/bios-disk.img \
  -device isa-debug-exit,iobase=0xf4,iosize=0x04 -serial stdio -display none -no-reboot
```

Oczekiwany wynik na końcu: `testkernel: WYNIK = PASS` i kod wyjścia QEMU
`33` — potwierdza to, że stage1 wczytał stage2, stage2 przeszedł real
mode → protected mode → long mode, poprawnie sparsował i skopiował ELF64
testowego jądra (higher-half, `0xFFFFFFFF80100000`) oraz nadał segmentom
`.text`/`.data` faktycznie różne uprawnienia stron (R+X bez NX vs R+W z
NX) — szczegóły w `bootloader/bios/test/README.md`.

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

Zakres testów jest **reprezentatywny, nie wyczerpujący**, ale `nimble
test` po raz pierwszy faktycznie działa end-to-end (wcześniej `tests/`
w ogóle nie istniało, mimo że `zenit_base.nimble` już się do niego
odwoływał — `nimble test` było całkowicie niesprawne). 86 testów łącznie:

- `tests/test_depgraph.nim` — sortowanie topologiczne kolejności startu
  usług zsrv, w tym cykle zależności i zależności spoza aktywnego zestawu
- `tests/test_service_parser.nim` — parsowanie plików `.zsrv` (sekcje w
  stylu systemd, komentarze na końcu linii, `ExecStart=` z cudzysłowami,
  sufiksy rozmiaru K/M/G, `Environment=` pojedyncze/wielokrotne/kumulujące
  się/z cudzysłowem) oraz `reloadServices` (zachowanie stanu runtime przy
  aktualizacji, dodawanie nowych usług, usuwanie tylko zatrzymanych)
- `tests/test_lexer.nim` — tokenizacja zesh (cudzysłowy, operatory,
  `$(...)` ze spacją w środku, `$((...))` rozwijanie arytmetyczne,
  przekierowania `2>`/`2>>`/`2>&1`)
- `tests/test_cmdhistory.nim` — rozwijanie odwołań do historii (`!!`,
  `!n`, `!prefix`), w tym przypadki błędne (brak zdarzenia)
- `tests/test_parser.nim` — `splitStatements`/`splitRawStatements`
  (potoki, `;`/`&&`/`||`, poszanowanie cudzysłowów przy podziale instrukcji)
- `tests/test_vars.nim` — parametry pozycyjne zesh (`$0`, `$1`..`$9`,
  `$@`, `$#`), w tym przypadki brzegowe (brak argumentów, indeks poza
  zakresem, `$10` jako `$1` + literalne `0`)

**Faktycznie zainstalowane i uruchomione** (nie tylko zasemblowane/
skompilowane w ciemno): `nim`, `crystal`, `nasm`, `qemu-system-x86_64`,
`gcc-mingw-w64-x86-64`, `ovmf` — wszystkie z `apt` (domeny
`archive.ubuntu.com`/`security.ubuntu.com`, w dozwolonej sieci
wychodzącej). `nimble test` przechodzi w całości (86/86),
`nimble buildShell`/`buildInit`/`buildBootloader` budują się czysto, a
prawdziwy `zsrv` (uruchomiony jako zwykły proces, z `zsrvctl` sterującym
przez gniazdo), prawdziwy `zesh` ORAZ prawdziwy `BOOTX64.EFI` (w
QEMU+OVMF, z ESP zawierającym `EFI/BOOT/BOOTX64.EFI`+`ZENIT/KERNEL.ELF`)
zostały ręcznie przećwiczone na żywo — patrz punkt "Trzy realne błędy..."
w sekcji `zsrv` wyżej, sekcja "Błąd fundamentalny... backend UEFI nigdy
wcześniej nie działał" wyżej, oraz sekcje o VBE/A20 w
`bootloader/bios/test/README.md` dla przykładów błędów złapanych WYŁĄCZNIE
dzięki temu, a niewidocznych przy samej kompilacji/asemblacji.

`spec/` pokrywa próbkę narzędzi CLI (`about`, `ar`, `cr`, `dl`, `echo`,
`gdz`, `id`, `kt`, `lb`, `mk`, `pf`, `ro`, `so`, `un`, `wp`, `wz`, `xa`)
oraz (nowość) `spec/demangle_spec.cr` — testy jednostkowe demanglera C++
(patrz niżej).
**Faktycznie uruchomione** w tej samej sesji: `crystal build --no-codegen`
na wszystkich 37 narzędziach z `shard.yml` (same typechecking, bez
pełnego linkowania — szybkie i wystarczające do złapania błędów typów)
— zero błędów; oraz `crystal spec` (`tools_spec.cr` + `demangle_spec.cr`
razem) na realnie zbudowanych binarkach (`crystal build --no-debug -o
bin/NAZWA ...` dla każdego targetu, ręcznie, bo `shards` nie jest tu
zainstalowane, tylko `crystal`) — **55/55 przykładów, 0 błędów** (46 z
`tools_spec.cr` + 9 z nowego `demangle_spec.cr`). W odróżnieniu od
zboot/zsrv z wcześniejszych sekcji, warstwa `tools/` okazała się w
większości bez niespodzianek — solidne potwierdzenie jakości kodu, który
już tu był, zamiast kolejnej listy złapanych błędów.

**Demangling C++ w `zdb`** (nowość, wcześniej TODO): `tools/zdb/src/demangle.cr`
implementuje podzbiór Itanium C++ ABI wystarczający dla większości
backtrace'ów spotykanych w praktyce — nazwy zagnieżdżone (namespace/
klasa), konstruktory/destruktory (`C1`/`C2`/`C3`, `D0`/`D1`/`D2`), typy
wbudowane, wskaźniki/referencje/`const`/`volatile`, oraz TABELĘ
PODSTAWIEŃ (`S_`, `S0_`, ...) — bez niej realne mangled names (gcc/clang
regularnie jej używają dla kompresji) demanglowałyby się źle albo wcale.
Szablony (`I...E`) i przeciążone operatory świadomie POZA zakresem —
zbyt złożona gramatyka jak na narzędzie-debugger, nie kompilator; w
takich przypadkach `demangle` zwraca oryginalny mangled name BEZ ZMIAN
(nigdy zmyślony/błędny wynik). Każdy przypadek w `demangle_spec.cr`
zweryfikowany wprost przeciwko `c++filt` (GNU binutils) podczas pisania
tego modułu — w tym rzeczywisty błąd off-by-one w indeksowaniu tabeli
podstawień złapany i naprawiony tą metodą (`_Z3fooPiS_` dawało błędnie
`foo(int*, foo)` zamiast `foo(int*, int*)`, bo gołe, niezagnieżdżone
nazwy funkcji na szczycie `_Z...` okazały się NIE być kandydatem do
tabeli podstawień w praktyce gcc/clang, wbrew pierwszemu odczytaniu
gramatyki). Dodatkowo przetestowane na PRAWDZIWYM binarium: `g++` z
klasą w namespace (konstruktor, destruktor, metoda), symbole odczytane
przez `zdb`'s `symbols` w żywej sesji debugowania (`ptrace`-owany
proces) — wynik identyczny z `nm ... | c++filt`.

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
skryptem** — backend UEFI trafia na partycję ESP jako
`\EFI\BOOT\BOOTX64.EFI`, backend BIOS (`stage1.bin`/`stage2.bin`) trafia
na MBR/wczesne sektory dysku rozruchowego — oba to zadanie
instalatora/administratora systemu, nie tego skryptu.

## Licencja

Cały projekt jest udostępniony na licencji **Apache License 2.0** — patrz
plik [LICENSE](./LICENSE).

## Status

Projekt jest we wczesnej fazie rozwoju (wszystkie komponenty: `0.1.0`).

- `zesh`: potoki/przekierowania/warunki, aliasy (**rekurencyjne, z
  wykrywaniem pętli**), **`$(...)`** (substytucja poleceń), **`$((...))`**
  (rozwijanie arytmetyczne — `+ - * / % < <= > >= == != && ||`, zmienne,
  liczby szesnastkowe), naprawione rozwijanie `$VAR` poza cudzysłowem oraz
  naprawione rozwijanie `$?`/`$(...)` per-instrukcja w linii z `;`/`&&`/`||`
  (wcześniej cała linia była rozwijana jednym rzutem na starcie, więc `$?`
  po `;` widział kod wyjścia sprzed całej linii, nie poprzedniej instrukcji).
  **Pełna kontrola terminala**: grupy procesów (`setpgid`) + oddawanie
  terminala pierwszoplanowemu zadaniu (`tcsetpgrp`), więc np. Ctrl+C trafia
  do uruchomionego polecenia, nie do samej powłoki; kod wyjścia procesu
  zabitego sygnałem raportowany jako `128+sygnał` (konwencja uniksowa).
  **Zatrzymywanie zadań przez Ctrl+Z i `bg`** (nowość): pierwszoplanowe
  zadanie zatrzymane sygnałem `SIGTSTP` (`waitpid` z `WUNTRACED` zamiast
  zwykłego `0` — inaczej powłoka czekałaby w nieskończoność na
  "zakończenie", które nigdy by nie nastąpiło) NIE znika, tylko dostaje
  numer zadania jak przy `polecenie &` (`jobcontrol.stopJob`) i trafia z
  powrotem pod kontrolę `zesh`. `fg %N` wysyła mu `SIGCONT`, oddaje
  terminal i czeka ponownie (obsługując też powtórny Ctrl+Z — zadanie
  wraca wtedy na listę jako zatrzymane, zamiast zniknąć); `bg %N` wysyła
  `SIGCONT` i od razu oddaje prompt, bez oddawania terminala grupie
  zadania — dokładnie jak w bashu. `jobs` pokazuje teraz trzy stany:
  `Running`/`Stopped`/`Done`; `refreshJobStatuses` wykrywa też
  samoistne zatrzymanie zadania w tle (np. próbę odczytu z terminala —
  `SIGTTIN`) przez `WNOHANG or WUNTRACED`.
- `zsrv`: epoll/signalfd, sortowanie topologiczne, cgroups v2, grupy
  procesów (`setsid`), **przełączanie targetu w locie** przez
  `/run/zenit/target`, dwufazowe zamykanie.
- `zboot`: **dwa niezależne backendy** — UEFI (Nim), higher-half,
  **mapowanie 4 KiB z uprawnieniami R/W/X per-segment ELF** i `EFER.NXE`;
  BIOS (NASM, `bootloader/bios/`), real mode → protected mode → long mode,
  ta sama higher-half + per-segment R/W/X logika, zweryfikowane end-to-end
  w QEMU testowym jądrem (`bootloader/bios/test/`). BIOS na tym etapie
  wczytuje jądro jako surowe sektory pod stałym LBA zamiast przez system
  plików (TODO: FAT, żeby dorównać wygodzie UEFI) i używa stałej fizycznej
  bazy jądra zamiast alokować ją dynamicznie (TODO).
- `tools/`: 37 narzędzi CLI w Crystalu, w tym `zdb` (symbole ELF +
  **demangling C++** w stylu Itanium ABI — podzbiór gramatyki
  (nazwy zagnieżdżone, ctor/dtor, wskaźniki/referencje/const, tabela
  podstawień), zweryfikowany przeciwko `c++filt` na 31 przypadkach
  testowych ORAZ na realnie skompilowanym binarium C++ (g++, symbole z
  `nm`) — patrz `spec/demangle_spec.cr` i sekcja niżej; deasemblacja),
  `ar` (prawdziwy ustar + gzip, ochrona przed path
  traversal), `ro` (**algorytm Myersa** zamiast poprzedniej tablicy DP
  O(n·m) -- patrz niżej), `xa` (**`-P`** uruchamianie równoległe +
  naprawione przekazywanie flag do polecenia docelowego -- patrz niżej)
  i uzupełnione `echo`, `printf`, `free`, `uptime`, `nice`.
- **Testy i instalacja**: `tests/` (Nim), `spec/` (Crystal),
  `scripts/install.sh` + `scripts/uninstall.sh`.

Rejestracja w menedżerach pakietów dystrybucji (dpkg/rpm/pacman) i pełne
pokrycie testami wszystkich 37 narzędzi pozostają świadomie poza zakresem
obecnego etapu.
