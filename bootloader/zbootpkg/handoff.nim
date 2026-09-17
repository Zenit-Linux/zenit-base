import ./memory
import ./graphics
import ./uefi_types
import ./console

# Rozmiar właściwego stosu jądra (bez strony strażniczej) — zachowuje
# poprzednie 64 KiB (16 stron po 4 KiB).
const KernelStackPages = 16'u64
const GuardPages = 1'u64
const PageSize4K = 0x1000'u64

proc allocKernelStack*(bs: ptr EfiBootServices): tuple[stackTop: uint64, guardPhys: uint64] =
  ## Alokuje stos jądra na wczesnym etapie rozruchu jako ODDZIELNY,
  ## page-aligned blok pamięci (zamiast poprzedniego statycznego bufora
  ## w BSS zboot), poprzedzony JEDNĄ dodatkową stroną przeznaczoną na
  ## guard page. Stos rośnie w dół, więc jego przepełnienie NAJPIERW
  ## trafi w tę stronę.
  ##
  ## Samą stronę trzeba dopiero "wybić" (oznaczyć jako not-present) w
  ## tablicach stron przez `zbootpkg/paging.punchGuardPage` — ta funkcja
  ## tylko alokuje pamięć i zwraca jej adres fizyczny (`guardPhys`) do
  ## przekazania tamtej funkcji, bo w tym module nie ma dostępu do
  ## `PageTables` (unika się w ten sposób zależności cyklicznej
  ## handoff <-> paging).
  ##
  ## `AllocatePages` z `AllocateAnyPages` nie gwarantuje ułożenia
  ## względem innych alokacji, więc bierzemy JEDNYM wywołaniem blok
  ## `GuardPages + KernelStackPages` stron CIĄGŁYCH i sami dzielimy go na
  ## "strona strażnicza | właściwy stos", zamiast dwóch osobnych alokacji,
  ## których wzajemna kolejność w pamięci nie byłaby zagwarantowana.
  var base: uint64 = 0
  let totalPages = GuardPages + KernelStackPages
  # AllocateAnyPages = 0, EfiLoaderData = 2
  let status = bs.allocatePages(0'u32, EfiMemoryType(2), totalPages.uint, addr base)
  if status != StatusSuccess:
    panic("nie udalo sie zaalokowac stosu jadra")

  let guardPhys = base
  let stackBase = base + GuardPages * PageSize4K
  let stackTop = (stackBase + KernelStackPages * PageSize4K - 1'u64) and not 0xF'u64
  (stackTop, guardPhys)

type
  BootInfo* = object
    ## UWAGA: layout MUSI być bajt-w-bajt zgodny z tym, co ręcznie zapisuje
    ## `bootloader/bios/stage2.asm` (sekcja wypełniania BOOTINFO_ADDR w
    ## entry64) — to jest WSPÓLNY kontrakt między obydwoma backendami
    ## (UEFI/Nim tutaj i BIOS/NASM tam), z którego korzysta jądro Zenit
    ## Linux niezależnie od tego, jak zostało uruchomione. Błąd znaleziony
    ## rzeczywistym testem w QEMU+OVMF: tej struktury brakowało pól
    ## `firmwareKind`/`memoryMapEntryCount`, mimo że backend BIOS je
    ## zapisuje pod stałymi offsetami (0x45/0x48) — jądro odczytujące
    ## `BootInfo` po starcie z UEFI czytałoby tam przypadkowe bajty
    ## pamięci zamiast rzeczywistych wartości. Naturalne wyrównanie tego
    ## `object` w Nim (bez `{.packed.}`) samo układa te pola na
    ## DOKŁADNIE tych offsetach (sprawdzone przez `sizeof`/`efiPrintHex`
    ## w trakcie debugowania), bo typy/kolejność pól są identyczne z tym,
    ## co robi ręcznie stage2.asm — ale gdyby ktoś kiedyś zmienił
    ## kolejność/typy pól, WARTO to ponownie zweryfikować w obu
    ## backendach naraz, a nie osobno.
    memoryMapAddr*:        uint64 # 0x00
    memoryMapSize*:        uint64 # 0x08
    memoryMapDescSize*:    uint64 # 0x10
    kernelBase*:           uint64 # 0x18
    kernelEntry*:          uint64 # 0x20
    fbBase*:               uint64 # 0x28
    fbSize*:                uint64 # 0x30
    fbWidth*:                uint32 # 0x38
    fbHeight*:                uint32 # 0x3C
    fbPixelsPerLine*:          uint32 # 0x40
    fbBgr*:                     bool  # 0x44
    firmwareKind*:                uint8 # 0x45 (0 = UEFI, 1 = BIOS)
    # 2 bajty wypełnienia (0x46-0x47) -- wstawiane automatycznie przez
    # wyrównanie kolejnego pola uint32 do granicy 4 bajtów, DOKŁADNIE tak
    # samo jak w stage2.asm (tam też jest tu luka, bo kolejne pole zaczyna
    # się od 0x48, nie 0x46).
    memoryMapEntryCount*:          uint32 # 0x48 -- memoryMapSize div memoryMapDescSize

proc buildBootInfo*(mmap: MemoryMapResult, kernelBase: uint64, kernelEntry: uint64,
                     fb: FramebufferInfo): BootInfo =
  BootInfo(
    memoryMapAddr:     cast[uint64](mmap.buffer),
    memoryMapSize:      uint64(mmap.size),
    memoryMapDescSize:  uint64(mmap.descriptorSize),
    kernelBase:        kernelBase,
    kernelEntry:       kernelEntry,
    fbBase:            fb.base,
    fbSize:            fb.size,
    fbWidth:           fb.width,
    fbHeight:          fb.height,
    fbPixelsPerLine:   fb.pixelsPerLine,
    fbBgr:             fb.bgr,
    firmwareKind:      0'u8, # 0 = UEFI (BIOS zapisuje 1, patrz stage2.asm)
    memoryMapEntryCount: uint32(uint64(mmap.size) div uint64(mmap.descriptorSize)),
  )

proc jumpToKernel*(bootInfo: ptr BootInfo, stackTop: uint64) {.noreturn.} =
  ## Przełącza się na dedykowany stos zboot (zaalokowany osobno przez
  ## `allocKernelStack`, z guard page'em wybitym przez
  ## `zbootpkg/paging.punchGuardPage` — patrz zboot.nim) i skacze do
  ## punktu wejścia jądra z `bootInfo` w RDI (System V AMD64 ABI —
  ## konwencja, jakiej oczekuje jądro Zenit Linux; różni się od MS x64
  ## ABI używanego przez UEFI, dlatego to przełączenie następuje jawnie
  ## w tym miejscu, a nie przez zwykłe wywołanie proc).
  ##
  ## TODO: opcjonalne przejście przez trampolinę 32-bit, jeśli kiedyś
  ## zajdzie potrzeba obsługi jąder uruchamianych w trybie zgodności
  ## zamiast pełnego long mode.
  ##
  ## Obsługa jąder higher-half (adres wirtualny != fizyczny) oraz
  ## uprawnienia per-segment (R/W/X wg p_flags ELF) są już zapewnione
  ## wcześniej, przez zbootpkg/paging.buildPageTables + activate(),
  ## wywoływane w zboot.nim przed tym skokiem — ten skok po prostu ufa,
  ## że CR3 już wskazuje na poprawne odwzorowanie.
  let entry = bootInfo.kernelEntry
  let infoPtr = cast[uint64](bootInfo)

  asm """
    mov rdi, %0
    mov rsp, %1
    xor rbp, rbp
    jmp %2
    :
    : "r"(`infoPtr`), "r"(`stackTop`), "r"(`entry`)
    : "rdi", "rsp", "rbp"
  """

  # Nieosiągalne w praktyce — powyższy `jmp` przekazuje sterowanie do
  # jądra i nigdy nie wraca. Pętla istnieje wyłącznie po to, aby spełnić
  # wymóg {.noreturn.} w oczach kompilatora.
  while true:
    discard
