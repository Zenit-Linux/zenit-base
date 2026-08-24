# Zenith Linux

**Zenith Linux** to dystrybucja Linuksa budowana od zera, uzależniona od GNU
(libc, toolchain itd.), ale zastępująca klasyczne narzędzia coreutils
własnymi, nowoczesnymi odpowiednikami — a docelowo także własnym
bootloaderem i systemem init.

## Filozofia

Zamiast klonować `coreutils` 1:1, Zenith pisze każde narzędzie od nowa,
w języku dobranym do jego charakteru, z naciskiem na:

- czytelne, kolorowe komunikaty błędów,
- bezpieczniejsze zachowania domyślne (np. `dl` domyślnie przenosi do kosza,
  a nie kasuje trwale),
- nowoczesny, spójny interfejs CLI (`--help`, `--version`, długie i krótkie flagi).

## Narzędzia CLI

Wszystkie narzędzia CLI są dziś napisane w **Crystalu** (jeden spójny,
skompilowany, statycznie typowany język dla całego zestawu). Powłoka `zesh`
oraz komponenty systemowe (`zboot`, `zsrv`) pozostają w **Nim**.

| Narzędzie | Zastępuje    | Status         | Opis                                          |
|-----------|--------------|----------------|------------------------------------------------|
| `zesh`    | `bash`       | działa (Nim)   | powłoka systemowa                               |
| `about`   | `uname`      | działa         | informacje o systemie                           |
| `cr`      | `mkdir`      | działa         | tworzenie katalogów                             |
| `dl`      | `rm`         | działa         | usuwanie plików/katalogów (z koszem)            |
| `mk`      | `touch`      | działa         | tworzenie plików / aktualizacja czasu           |
| `ow`      | `chown`      | działa         | zmiana właściciela                              |
| `gr`      | `chgrp`      | działa         | zmiana grupy                                    |
| `pm`      | `chmod`      | działa         | zmiana uprawnień                                |
| `rm`      | `mv`         | działa         | przenoszenie / zmiana nazwy                     |
| `sp`      | `ls`         | szkielet       | listowanie zawartości katalogów                 |
| `kp`      | `cp`         | szkielet       | kopiowanie plików/katalogów                     |
| `wp`      | `cat`        | szkielet       | wypisywanie zawartości plików                   |
| `sz`      | `grep`       | szkielet       | wyszukiwanie wzorców w tekście                  |
| `zn`      | `find`       | szkielet       | wyszukiwanie plików w drzewie katalogów         |
| `lb`      | `wc`         | szkielet       | liczenie linii / słów / bajtów                  |
| `wz`      | `ln`         | szkielet       | dowiązania twarde i symboliczne                 |
| `pr`      | `ps`         | szkielet       | listowanie procesów (z `/proc`)                 |

„Szkielet” oznacza, że interfejs CLI i podstawowa ścieżka działania są
gotowe, ale bardziej zaawansowane opcje są oznaczone komentarzami `TODO`
bezpośrednio w kodzie źródłowym — to naturalne miejsca do kontynuowania
rozwoju.

> Historia: `cr`, `dl` i `mk` były pierwotnie zapisane jako pliki `.cr`
> zawierające kod źródłowy Nim (pomyłka nazewnicza). Zostały przepisane na
> właściwy Crystal, zachowując pełną funkcjonalność oryginału.

## Komponenty systemowe (Nim)

| Komponent | Rola                          | Status   |
|-----------|-------------------------------|----------|
| `zboot`   | bootloader (Multiboot2, x86)  | szkielet |
| `zsrv`    | system init / PID 1           | szkielet |

### `zboot` — bootloader

Skompilowany w trybie `--os:standalone` (bez libc/GC), zgodny z nagłówkiem
**Multiboot2** — może być załadowany przez GRUB2 lub bezpośrednio przez QEMU.
Zaimplementowano: nagłówek Multiboot2, wyjście tekstowe VGA, szkielet
parsowania mapy pamięci i wczytywania jądra, panic handler. Do zrobienia
(oznaczone `TODO` w kodzie): parsowanie tagów Multiboot2, sterownik
odczytu z dysku / systemu plików, przejście do trybu long mode i
przekazanie sterowania do jądra.

### `zsrv` — system init (PID 1)

Wczytuje definicje usług z `/etc/zenit/services/*.zsrv` (prosty format
`Klucz=wartość`), uruchamia je z uwzględnieniem zależności (`After=`),
nadzoruje cykl życia (polityki `Restart=always|on-failure|never`) i zbiera
zombie przez `waitpid` w handlerze `SIGCHLD`. Do zrobienia: sortowanie
topologiczne zależności, przeładowanie konfiguracji po `SIGHUP`,
cgroups, pętla zdarzeń oparta o `signalfd`/`epoll` zamiast pollingu.

## Propozycje kolejnych narzędzi

Poza tymi już dodanymi jako szkielety (`sp`, `kp`, `wp`, `sz`, `zn`, `lb`,
`wz`, `pr`), warto rozważyć w kolejnych etapach:

- `df` / `du` — zajętość miejsca na dyskach i w katalogach,
- `head` / `tail` — podgląd początku/końca pliku (w tym `-f` jak `tail -f`),
- `kill` / `zabij` — wysyłanie sygnałów do procesów (naturalne uzupełnienie `pr`),
- `sort` / `uniq` — sortowanie i deduplikacja linii,
- `tar`-podobne narzędzie archiwizujące,
- `which` / `env` / `id` / `whoami` / `hostname` — drobne narzędzia diagnostyczne,
- `diff` — porównywanie plików tekstowych.

## Struktura repozytorium

```
zenith-linux/
├── shard.yml                  # definicje WSZYSTKICH narzędzi Crystal
├── zenit-base.nimble           # definicje komponentów Nim (zesh, zboot, zsrv)
├── build.janet                  # orkiestrator budowy całości
├── .github/workflows/
│   ├── build-all.yml             # CI: buduje i pakuje wszystko
│   ├── build-tools.yml            # CI: narzędzia CLI (Crystal + zesh)
│   ├── build-bootloader.yml        # CI: zboot (szkielet, --os:standalone)
│   └── build-init-system.yml        # CI: zsrv
├── zesh/                              # powłoka (Nim)
├── bootloader/
│   └── zboot.nim                       # bootloader (Nim, standalone) — szkielet
├── init-system/
│   └── zsrv.nim                         # system init / PID 1 (Nim) — szkielet
└── tools/                                # wszystkie narzędzia CLI (Crystal)
    ├── about/src/about.cr
    ├── cr/src/cr.cr
    ├── dl/src/dl.cr
    ├── mk/src/mk.cr
    ├── ow/src/ow.cr
    ├── gr/src/gr.cr
    ├── pm/src/pm.cr
    ├── rm/src/rm.cr
    ├── sp/src/sp.cr
    ├── kp/src/kp.cr
    ├── wp/src/wp.cr
    ├── sz/src/sz.cr
    ├── zn/src/zn.cr
    ├── lb/src/lb.cr
    ├── wz/src/wz.cr
    └── pr/src/pr.cr
```

## Budowanie

Wymagania: Nim ≥ 2.0, Crystal ≥ 1.10, Janet, GNU toolchain (a dla
bootloadera dodatkowo: nasm, GRUB, QEMU — patrz `build-bootloader.yml`).

```bash
# Powłoka zesh (Nim)
nimble buildShell

# System init zsrv (Nim)
nimble buildInit

# Bootloader zboot (Nim, --os:standalone, szkielet)
nimble buildBootloader

# Wszystkie komponenty Nim naraz
nimble buildAll

# Narzędzia CLI (Crystal)
shards install
shards build --release

# Albo całość naraz, przez orkiestrator:
janet build.janet
```

Wynikowe binaria trafiają do katalogu `dist/`.

## Licencja

Cały projekt jest udostępniony na licencji **Apache License 2.0** — patrz
plik [LICENSE](./LICENSE).

## Status

Projekt jest we wczesnej fazie rozwoju. `zesh` obsługuje na razie proste
polecenia natywnie, a bardziej złożone konstrukcje (potoki wieloetapowe,
przekierowania) deleguje tymczasowo do `/bin/sh` — docelowo ma powstać
natywny silnik parsowania i wykonywania poleceń. `zboot` i `zsrv` są
szkieletami architektonicznymi gotowymi do dalszej implementacji — patrz
komentarze `TODO` w ich kodzie źródłowym.
