import ./memory
import ./graphics

const KernelStackSize = 64 * 1024

# Statyczny bufor na stos jądra na etapie wczesnego rozruchu — celowo NIE
# jest to zmienna lokalna proc jumpToKernel, żeby jej adres nie zależał od
# aktualnej ramki stosu, którą i tak porzucamy.
var gKernelStack {.align: 16.}: array[KernelStackSize, uint8]

type
  BootInfo* = object
    memoryMapAddr*:      uint64
    memoryMapSize*:      uint64
    memoryMapDescSize*:  uint64
    kernelBase*:         uint64
    kernelEntry*:        uint64
    fbBase*:             uint64
    fbSize*:             uint64
    fbWidth*:            uint32
    fbHeight*:           uint32
    fbPixelsPerLine*:    uint32
    fbBgr*:              bool

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
  )

proc jumpToKernel*(bootInfo: ptr BootInfo) {.noreturn.} =
  ## Przełącza się na dedykowany stos zboot i skacze do punktu wejścia
  ## jądra z `bootInfo` w RDI (System V AMD64 ABI — konwencja, jakiej
  ## oczekuje jądro Zenit Linux; różni się od MS x64 ABI używanego przez
  ## UEFI, dlatego to przełączenie następuje jawnie w tym miejscu, a nie
  ## przez zwykłe wywołanie proc).
  ##
  ## TODO: 1) przekazanie większego stosu / stosu z guard page zamiast
  ##          stałego bufora 64 KiB,
  ##       2) opcjonalne przejście przez trampolinę 32-bit, jeśli kiedyś
  ##          zajdzie potrzeba obsługi jąder uruchamianych w trybie
  ##          zgodności zamiast pełnego long mode.
  ##
  ## Obsługa jąder higher-half (adres wirtualny != fizyczny) oraz
  ## uprawnienia per-segment (R/W/X wg p_flags ELF) są już zapewnione
  ## wcześniej, przez zbootpkg/paging.buildPageTables + activate(),
  ## wywoływane w zboot.nim przed tym skokiem — ten skok po prostu ufa,
  ## że CR3 już wskazuje na poprawne odwzorowanie.
  let stackTop = (cast[uint64](addr gKernelStack[KernelStackSize - 1]) and not 0xF'u64)
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
