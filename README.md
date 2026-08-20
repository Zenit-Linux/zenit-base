# Zenith Linux

**Zenith Linux** to dystrybucja Linuksa budowana od zera, uzależniona od GNU
(libc, toolchain itd.), ale zastępująca klasyczne narzędzia coreutils
własnymi, nowoczesnymi odpowiednikami.

## Filozofia

Zamiast klonować `coreutils` 1:1, Zenith pisze każde narzędzie od nowa,
w języku dobranym do jego charakteru, z naciskiem na:

- czytelne, kolorowe komunikaty błędów,
- bezpieczniejsze zachowania domyślne (np. `dl` domyślnie przenosi do kosza,
  a nie kasuje trwale),
- nowoczesny, spójny interfejs CLI (`--help`, `--version`, długie i krótkie flagi).

## Narzędzia

| Narzędzie | Zastępuje | Język     | Opis                                   |
|-----------|-----------|-----------|-----------------------------------------|
| `zesh`    | `bash`    | Nim       | powłoka systemowa                       |
| `about`   | `uname`   | Crystal   | informacje o systemie                   |
| `cr`      | `mkdir`   | Nim       | tworzenie katalogów                     |
| `dl`      | `rm`      | Nim       | usuwanie plików/katalogów (z koszem)    |
| `mk`      | `touch`   | Nim       | tworzenie plików / aktualizacja czasu   |
| `ow`      | `chown`   | Crystal   | zmiana właściciela                      |
| `gr`      | `chgrp`   | Crystal   | zmiana grupy                            |
| `pm`      | `chmod`   | Crystal   | zmiana uprawnień                        |

Więcej narzędzi (zastępujących m.in. `ls`, `cp`, `mv`, `cat`, `grep`) jest
zaplanowanych na kolejne etapy rozwoju projektu.

## Struktura repozytorium

```
zenith-linux/
├── shard.yml              # definicje narzędzi Crystal (about, ow, gr, pm)
├── tools.nimble            # definicje narzędzi Nim (zesh, cr, dl, mk)
├── build.janet              # orkiestrator budowy całości
├── .github/workflows/
│   └── build-all.yml        # CI: buduje i publikuje wszystkie binaria
├── zesh/                     # powłoka (Nim)
├── cr/                        # mkdir (Nim)
├── dl/                         # rm (Nim)
├── mk/                          # touch (Nim)
├── about/src/                    # uname (Crystal)
├── ow/src/                         # chown (Crystal)
├── gr/src/                          # chgrp (Crystal)
└── pm/src/                           # chmod (Crystal)
```

## Budowanie

Wymagania: Nim ≥ 2.0, Crystal ≥ 1.10, Janet, GNU toolchain.

```bash
# Narzędzia Nim
nimble build -d:release -y

# Narzędzia Crystal
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
natywny silnik parsowania i wykonywania poleceń.
