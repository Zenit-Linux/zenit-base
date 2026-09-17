import ./memory
import ./filesystem
import ./handoff

type
  BootBackend* = object
    ## Zestaw procedur, jakie musi dostarczyć każdy backend firmware.
    ## Backend UEFI (domyślny, patrz bootloader/zboot.nim) wypełnia te
    ## pola procedurami z zbootpkg/console, zbootpkg/memory i
    ## zbootpkg/filesystem.
    ##
    ## Backend BIOS (bootloader/bios/stage1.asm + stage2.asm) implementuje
    ## RÓWNOWAŻNĄ funkcjonalność, ale -- jak przewidywano w poprzedniej
    ## wersji tego komentarza -- jako CAŁKOWICIE OSOBNĄ binarkę (MBR +
    ## drugi etap), a nie jako wypełnienie tego obiektu `BootBackend` w
    ## Nimie. Powód jest fundamentalny, nie tylko organizacyjny: BIOS
    ## startuje procesor w 16-bitowym trybie rzeczywistym, do którego nie
    ## da się skompilować kodu Nim (ani żadnego innego języka zakładającego
    ## współczesne ABI/model pamięci) -- kod musi ręcznie przeprowadzić
    ## przejście real mode -> protected mode -> long mode w asemblerze,
    ## zanim cokolwiek "wysokopoziomowego" ma szansę się wykonać. Backend
    ## BIOS realizuje więc TĘ SAMĄ umowę co `BootBackend` (mapa pamięci,
    ## wczytanie jądra, przekazanie BootInfo/wejście do jądra), tylko
    ## bezpośrednio w NASM zamiast przez te pola-procedury:
    ##   - printText      -> zbootpkg/console (UEFI ConOut)      vs port szeregowy COM1 w stage2.asm. BIOS koduje TEŻ tekst na COM1 jako telnet-owalny wyjściowy log (patrz `print_string`/`serial_print` w stage2.asm) -- ma też od niedawna `detect_vbe` ustawiające tryb graficzny VBE (framebuffer liniowy dla jądra), ale to WYŁĄCZNIE tryb graficzny bez renderowania czcionek: nie ma i nie planuje się odpowiednika tekstowego ConOut rysowanego na tym framebufferze -- diagnostyka BIOS-u zawsze idzie przez COM1, nie przez ekran.
    ##   - getMemoryMap   -> zbootpkg/memory (EFI GetMemoryMap)  vs INT 15h/EAX=0xE820 w stage2.asm::detect_memory
    ##   - loadKernelBytes -> zbootpkg/filesystem (Simple File System, \ZENIT\KERNEL.ELF na ESP) vs surowe sektory pod stałym LBA w stage2.asm::load_kernel_image (BIOS nie parsuje żadnego systemu plików na tym etapie -- TODO: FAT, żeby dopasować się do wygody UEFI)
    ##   - handoffToKernel -> zbootpkg/handoff (asm inline w C)  vs stage2.asm::entry64 (parsowanie ELF64, mapowanie per-segment, skok do jądra)
    printText*:       proc(s: string)
    getMemoryMap*:    proc(): MemoryMapResult
    loadKernelBytes*: proc(path: string): LoadedKernel
    handoffToKernel*: proc(info: ptr BootInfo) {.noreturn.}

  FirmwareKind* = enum
    fwUefi  ## Nim, bootloader/zboot.nim + zbootpkg/*, wypełnia BootBackend powyżej.
    fwBios  ## NASM, bootloader/bios/stage1.asm + stage2.asm -- osobna binarka, patrz komentarz przy BootBackend.

proc detectFirmwareKind*(): FirmwareKind =
  ## Ta procedura dotyczy WYŁĄCZNIE binarki UEFI (bootloader/zboot.nim,
  ## task `buildBootloader`) -- backend BIOS jest, jak opisano przy
  ## `BootBackend` powyżej, całkowicie osobną binarką (bootloader/bios/),
  ## która nigdy nie woła tej procedury i nie jest budowana przez Nima
  ## w ogóle, więc nie ma tu "wykrywania w locie" między dwoma backendami
  ## -- decyzję, którą binarkę wgrać na ESP/MBR, podejmuje się przy
  ## instalacji/budowie obrazu dysku, nie w runtime. Dlatego ta procedura
  ## zawsze zwraca fwUefi -- to nie jest TODO, to jest zamierzony,
  ## ostateczny kształt architektury.
  fwUefi

