version       = "0.2.0"
author        = "Zenith Linux Developers"
description   = "Rdzenne komponenty Zenith Linux napisane w Nim: powłoka zesh, bootloader zboot i system init zsrv"
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

task buildBootloader, "Buduje bootloader zboot jako binarkę standalone":
  # Bootloader nie może zależeć od libc/systemowego runtime'u Nim,
  # dlatego kompilujemy go w trybie --os:standalone.
  # TODO: docelowo dodać własny linker script i cel `-d:release --opt:size`
  # dopasowany do trybu rzeczywistego x86 (16-bit) / UEFI, w zależności
  # od wybranej architektury rozruchu.
  exec "nim c -d:release --os:standalone --gc:none --out:bootloader/zboot bootloader/zboot.nim"

task buildAll, "Buduje wszystkie komponenty Nim (zesh, zsrv, zboot)":
  exec "nimble buildShell"
  exec "nimble buildInit"
  exec "nimble buildBootloader"

task test, "Uruchamia podstawowe testy dymne narzędzi Nim":
  exec "nim c -r zesh/zesh.nim --version"
