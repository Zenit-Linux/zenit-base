version       = "0.3.0"
author        = "Zenith Linux Developers"
description   = "Rdzenne komponenty Zenith Linux napisane w Nim: powłoka zesh, bootloader zboot i system init zsrv (każdy rozbity na moduły w katalogach *pkg/)"
license       = "Apache-2.0"

# Jedyny komponent budowany jako zwykły, natywny binarny plik przez `nimble build`.
# zboot (bootloader, --os:standalone) i zsrv (init/PID 1) mają własne zadania
# poniżej, ponieważ wymagają nietypowych flag kompilacji.
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
  # `gcc-mingw-w64-x86-64` (patrz .github/workflows/build-bootloader.yml).
  exec "nim c -d:release --os:any --cpu:amd64 --gc:none " &
       "--cc:gcc --gcc.exe:x86_64-w64-mingw32-gcc --gcc.linkerexe:x86_64-w64-mingw32-gcc " &
       "--passC:\"-mabi=ms\" " &
       "--passL:\"-nostdlib -Wl,--subsystem,10 -Wl,-e,efi_main -Wl,--oformat=binary\" " &
       "--out:bootloader/BOOTX64.EFI bootloader/zboot.nim"

task buildAll, "Buduje wszystkie komponenty Nim (zesh, zsrv, zboot)":
  exec "nimble buildShell"
  exec "nimble buildInit"
  exec "nimble buildBootloader"

task test, "Uruchamia podstawowe testy dymne narzędzi Nim":
  exec "nim c -r zesh/zesh.nim --version"
