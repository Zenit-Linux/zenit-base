version       = "0.1.0"
author        = "Zenit Linux Developers"
description   = "Rdzenne komponenty Zenit Linux napisane w Nim: powłoka zesh, bootloader zboot i system init zsrv (każdy rozbity na moduły w katalogach *pkg/)"
license       = "Apache-2.0"

# Jedyny komponent budowany jako zwykły, natywny binarny plik przez `nimble build`.
# zboot (bootloader, --os:any + własny alokator, patrz zbootpkg/allocator.nim)
# i zsrv (init/PID 1) mają własne zadania poniżej, ponieważ wymagają
# nietypowych flag kompilacji.
bin           = @["zesh/zesh"]
srcDir        = "."

requires "nim >= 2.0.0"

task buildShell, "Buduje powłokę zesh w trybie release":
  exec "nim c -d:release --out:zesh/zesh zesh/zesh.nim"

task buildInit, "Buduje system init zsrv (PID 1) w trybie release":
  exec "nim c -d:release --out:init-system/zsrv init-system/zsrv.nim"

task buildBootloader, "Buduje bootloader zboot jako aplikację UEFI (BOOTX64.EFI)":
  # zboot celuje wyłącznie w UEFI x86_64 na tym etapie (wsparcie BIOS
  # planowane jest jako osobny plugin, patrz komentarz w bootloader/zboot.nim).
  #
  # UEFI wymaga obrazu PE32+ z subsystemem EFI_APPLICATION (10) i konwencji
  # wywołań MS x64 ABI, dlatego krzyżowo kompilujemy przez mingw-w64 zamiast
  # domyślnego GCC/System V ABI. Wymaga zainstalowanego pakietu
  # `gcc-mingw-w64-x86-64` (patrz build.janet::ensure-mingw i
  # .github/workflows/build-bootloader.yml).
  #
  # --mm:arc -d:useMalloc: `--os:any` (poprawne dla programu freestanding)
  # nie ma domyślnego alokatora pamięci w bibliotece standardowej Nima —
  # `-d:useMalloc` każe Nimowi wywoływać zwykłe malloc/free/realloc, które
  # SAMI dostarczamy w zbootpkg/allocator.nim (przez UEFI AllocatePool),
  # zamiast pozwolić Nimowi szukać nieistniejącego alokatora "specyficznego
  # dla systemu" (błąd kompilacji "Port memory manager to your platform").
  # ARC (zamiast starszego "gc:none"/"mm:none") jest wymagane, bo kod
  # zboot używa `string`/`seq`, którym bez ŻADNEGO zarządzania pamięcią
  # ("mm:none") te typy w ogóle nie działają.
  #
  # -masm=intel: zbootpkg/handoff.nim zawiera wstawkę asemblerową
  # (przełączenie stosu + skok do jądra) napisaną w składni Intel
  # (`mov rdi, %0`, bez `%`-prefiksów rejestrów) -- domyślnie GCC oczekuje
  # składni AT&T i bez tej flagi kompilacja C kończy się w assemblerze
  # błędem "operand size mismatch for `xor'" (rejestr bez `%` jest
  # interpretowany jako symbol, nie rejestr).
  #
  # BRAK --oformat=binary: plik .EFI MUSI być poprawnym obrazem PE32+
  # (tak wygląda format "UEFI application") -- `--oformat=binary` każe
  # linkerowi wyprodukować surowy binarny blob bez nagłówka PE, co jest
  # sprzeczne z `-Wl,--subsystem,10`/`-Wl,-e,efi_main` (opcje specyficzne
  # dla PE) i kończyło się błędem linkera "cannot perform PE operations on
  # non PE output file". mingw-w64 domyślnie i tak produkuje PE32+.
  #
  # zbootpkg/crt_shim.nim dostarcza resztę symboli C (memcpy/memset/
  # calloc/strlen -- prawdziwe implementacje; signal/exit/fflush/fwrite/
  # __acrt_iob_func/__main -- bezpieczne no-opy), których żąda linker przy
  # `-nostdlib` (brak libc) -- bez tego linkowanie kończy się dziesiątkami
  # "undefined reference to 'memcpy'" itd.
  exec "nim c -d:release --os:any --cpu:amd64 --mm:arc -d:useMalloc " &
       "--cc:gcc --gcc.exe:x86_64-w64-mingw32-gcc --gcc.linkerexe:x86_64-w64-mingw32-gcc " &
       "--passC:\"-mabi=ms -masm=intel\" " &
       "--passL:\"-nostdlib -Wl,--subsystem,10 -Wl,-e,efi_main\" " &
       "--out:bootloader/BOOTX64.EFI bootloader/zboot.nim"

task buildAll, "Buduje wszystkie komponenty Nim (zesh, zsrv, zboot)":
  exec "nimble buildShell"
  exec "nimble buildInit"
  exec "nimble buildBootloader"

task test, "Uruchamia testy jednostkowe komponentów Nim (patrz tests/)":
  # Testy pokrywają czystą logikę (parsowanie, sortowanie zależności,
  # tokenizacja) bez potrzeby bycia rootem/PID 1 czy forkowania procesów.
  # Integracyjne testy narzędzi Crystal są osobno w spec/ (patrz `crystal spec`).
  exec "nim c -r tests/test_depgraph.nim"
  exec "nim c -r tests/test_service_parser.nim"
  exec "nim c -r tests/test_lexer.nim"
  exec "nim c -r tests/test_parser.nim"
  echo "\nWszystkie testy Nim przeszły pomyślnie."

task install, "Instaluje zbudowane binaria do systemu (PREFIX=/usr/local domyślnie)":
  exec "bash scripts/install.sh"

task uninstall, "Usuwa zainstalowane wcześniej binaria":
  exec "bash scripts/uninstall.sh"
