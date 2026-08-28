import ./memory
import ./filesystem
import ./handoff

type
  BootBackend* = object
    ## Zestaw procedur, jakie musi dostarczyć każdy backend firmware.
    ## Backend UEFI (domyślny, patrz bootloader/zboot.nim) wypełnia te
    ## pola procedurami z zbootpkg/console, zbootpkg/memory i
    ## zbootpkg/filesystem. Przyszły backend BIOS wypełni je własnymi
    ## odpowiednikami (np. wypisywanie przez port VGA 0xB8000 zamiast
    ## ConOut, odczyt dysku przez INT 13h zamiast Simple File System).
    printText*:       proc(s: string)
    getMemoryMap*:    proc(): MemoryMapResult
    loadKernelBytes*: proc(path: string): LoadedKernel
    handoffToKernel*: proc(info: ptr BootInfo) {.noreturn.}

  FirmwareKind* = enum
    fwUefi  ## jedyny wspierany na tym etapie
    fwBios  ## TODO: zarezerwowane dla przyszłego pluginu

proc detectFirmwareKind*(): FirmwareKind =
  ## Na tym etapie zboot jest budowany wyłącznie jako aplikacja UEFI
  ## (patrz task `buildBootloader` w zenit_base.nimble), więc wykrywanie
  ## firmware jest tu formalnością — zawsze zwraca fwUefi. Gdy powstanie
  ## plugin BIOS, ten projekt najprawdopodobniej pozostanie dwoma
  ## oddzielnymi binarkami (BOOTX64.EFI vs MBR/VBR), a nie jednym
  ## programem wykrywającym firmware w locie — TODO: decyzja architektoniczna
  ## do podjęcia przy projektowaniu pluginu BIOS.
  fwUefi
