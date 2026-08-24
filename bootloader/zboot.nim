{.push checks: off, stackTrace: off, lineTrace: off.}

# --------------------------------------------------------------------------
# Nagłówek Multiboot2 — umieszczony w dedykowanej sekcji linkera, tak aby
# GRUB/QEMU mogły go znaleźć w pierwszych 32 KiB obrazu.
# --------------------------------------------------------------------------

const
  Multiboot2Magic     = 0xE85250D6'u32
  Multiboot2ArchI386  = 0'u32
  HeaderLength        = 24'u32 # nagłówek + jeden tag "end"

type
  Multiboot2Header = object
    magic:        uint32
    architecture: uint32
    headerLength: uint32
    checksum:     uint32
    # Tag końcowy (typ 0, rozmiar 8) — na razie nie dodajemy tagów opcjonalnych
    # (np. framebuffer). TODO: dodać tag żądający trybu graficznego.
    endTagType:   uint16
    endTagFlags:  uint16
    endTagSize:   uint32

{.codegenDecl: "__attribute__((section(\".multiboot2\"), aligned(8))) $# $#$#".}
let multibootHeader = Multiboot2Header(
  magic:        Multiboot2Magic,
  architecture: Multiboot2ArchI386,
  headerLength: HeaderLength,
  checksum:     (0'u32 - (Multiboot2Magic + Multiboot2ArchI386 + HeaderLength)),
  endTagType:   0'u16,
  endTagFlags:  0'u16,
  endTagSize:   8'u32,
)

# --------------------------------------------------------------------------
# Prymitywy niskiego poziomu: port I/O oraz bezpośredni zapis do pamięci VGA.
# --------------------------------------------------------------------------

proc outb(port: uint16, value: uint8) {.inline.} =
  asm """
    outb %0, %1
    ::"a"(`value`), "Nd"(`port`)
  """

proc inb(port: uint16): uint8 {.inline.} =
  var res: uint8
  asm """
    inb %1, %0
    :"=a"(`res`)
    :"Nd"(`port`)
  """
  res

const
  VgaWidth  = 80
  VgaHeight = 25
  VgaColorDefault = 0x0F'u16 shl 8 # biały na czarnym

let vgaBuffer = cast[ptr UncheckedArray[uint16]](0xB8000)
var cursorRow = 0
var cursorCol = 0

proc vgaClear() =
  for i in 0 ..< (VgaWidth * VgaHeight):
    vgaBuffer[i] = VgaColorDefault or uint16(' ')
  cursorRow = 0
  cursorCol = 0

proc vgaPutChar(c: char) =
  if c == '\n':
    cursorCol = 0
    inc cursorRow
  else:
    let pos = cursorRow * VgaWidth + cursorCol
    vgaBuffer[pos] = VgaColorDefault or uint16(c)
    inc cursorCol
    if cursorCol >= VgaWidth:
      cursorCol = 0
      inc cursorRow
  # TODO: przewijanie ekranu, gdy cursorRow >= VgaHeight

proc vgaPrint(s: string) =
  for c in s:
    vgaPutChar(c)

proc panic(msg: string) {.noreturn.} =
  vgaPrint("\n[zboot] PANIKA: ")
  vgaPrint(msg)
  vgaPrint("\nSystem zatrzymany.\n")
  while true:
    asm "hlt"

# --------------------------------------------------------------------------
# Struktury przekazywane przez Multiboot2 (mapa pamięci, moduły, itd.)
# --------------------------------------------------------------------------

type
  MultibootInfo = object
    totalSize: uint32
    reserved:  uint32
    # TODO: iterować po tagach (typ, rozmiar) do znalezienia mmap (typ 6)
    # oraz informacji o module z obrazem jądra (typ 3), jeśli GRUB przekaże
    # go jako moduł startowy.

  MemoryRegion = object
    base:   uint64
    length: uint64
    kind:   uint32 # 1 = dostępna, inne = zarezerwowana/urządzenia

proc parseMemoryMap(info: ptr MultibootInfo): int =
  ## Zwraca liczbę znalezionych regionów pamięci.
  ## TODO: właściwe parsowanie tagów Multiboot2 (obecnie zaślepka).
  vgaPrint("[zboot] TODO: parsowanie mapy pamieci Multiboot2\n")
  0

# --------------------------------------------------------------------------
# Wczytywanie obrazu jądra Zenith Linux.
# --------------------------------------------------------------------------

const
  KernelLoadAddress = 0x100000'u64 # 1 MiB — standardowe miejsce dla jąder x86

proc locateKernelImage(info: ptr MultibootInfo): bool =
  ## Znajduje obraz jądra przekazany jako moduł Multiboot2 (GRUB `module2`)
  ## albo — w wersji docelowej — odczytuje go z partycji /boot poprzez
  ## własny, minimalny sterownik systemu plików (ext2/FAT).
  ##
  ## TODO: 1) obsługa modułu Multiboot2 (najprostsza ścieżka — bez sterownika FS)
  ##       2) minimalny sterownik odczytu z dysku (AHCI/ATA PIO) + parser ext2/FAT
  ##       3) weryfikacja formatu obrazu jądra (np. własny prosty nagłówek zkernel)
  vgaPrint("[zboot] TODO: lokalizacja obrazu jadra\n")
  false

proc loadKernelImage(destination: uint64): bool =
  ## Kopiuje obraz jądra pod docelowy adres w pamięci fizycznej.
  ## TODO: implementacja kopiowania + weryfikacja sumy kontrolnej.
  vgaPrint("[zboot] TODO: wczytywanie obrazu jadra do pamieci\n")
  false

# --------------------------------------------------------------------------
# Przejście sterowania do jądra.
# --------------------------------------------------------------------------

type
  BootInfo = object
    ## Struktura przekazywana do jądra Zenith Linux w rejestrze (np. RDI
    ## w ABI System V dla long mode). Definicja współdzielona z jądrem —
    ## docelowo powinna trafić do wspólnego nagłówka.
    memoryMapAddr: uint64
    memoryMapLen:  uint32
    kernelBase:    uint64

proc jumpToKernel(entryPoint: uint64, bootInfo: ptr BootInfo) {.noreturn.} =
  ## TODO: przejście z trybu chronionego (32-bit) do long mode (64-bit):
  ##   1) włączenie PAE (CR4)
  ##   2) załadowanie tablic stron identity-mapping pierwszych kilku MiB
  ##   3) ustawienie EFER.LME (long mode enable) przez MSR 0xC0000080
  ##   4) włączenie stronicowania (CR0.PG) — od tego momentu jesteśmy w
  ##      trybie zgodności (compatibility mode)
  ##   5) załadowanie 64-bitowego GDT i dalekiego skoku do segmentu kodu
  ##      64-bit, co przełącza CPU w pełny long mode
  ##   6) skok do `entryPoint` z `bootInfo` w RDI
  panic("jumpToKernel: nie zaimplementowano (patrz TODO)")

# --------------------------------------------------------------------------
# Punkt wejścia.
# --------------------------------------------------------------------------

proc zbootMain(multibootMagic: uint32, mbInfo: ptr MultibootInfo) {.exportc: "zboot_main", noreturn.} =
  vgaClear()
  vgaPrint("zboot -- bootloader Zenith Linux\n")
  vgaPrint("=================================\n\n")

  if multibootMagic != 0x36D76289'u32:
    panic("nieprawidlowe magic Multiboot2 - bootloader zaladowany niepoprawnie")

  discard parseMemoryMap(mbInfo)

  if not locateKernelImage(mbInfo):
    panic("nie znaleziono obrazu jadra Zenith Linux")

  if not loadKernelImage(KernelLoadAddress):
    panic("blad wczytywania obrazu jadra")

  var bootInfo = BootInfo(
    memoryMapAddr: 0,
    memoryMapLen: 0,
    kernelBase: KernelLoadAddress,
  )

  vgaPrint("\n[zboot] Przekazywanie sterowania do jadra...\n")
  jumpToKernel(KernelLoadAddress, addr bootInfo)

{.pop.}
