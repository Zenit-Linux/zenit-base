import ./console
import ./memory

type
  BootInfo* = object
    memoryMapAddr*:      uint64
    memoryMapSize*:      uint64
    memoryMapDescSize*:  uint64
    kernelBase*:         uint64
    kernelEntry*:        uint64

proc buildBootInfo*(mmap: MemoryMapResult, kernelBase: uint64, kernelEntry: uint64): BootInfo =
  BootInfo(
    memoryMapAddr:     cast[uint64](mmap.buffer),
    memoryMapSize:      uint64(mmap.size),
    memoryMapDescSize:  uint64(mmap.descriptorSize),
    kernelBase:        kernelBase,
    kernelEntry:       kernelEntry,
  )

proc jumpToKernel*(bootInfo: ptr BootInfo) {.noreturn.} =
  ## TODO: po ExitBootServices firmware nie jest już dostępne — brakuje:
  ##   1) przełączenia na własny stos przygotowany przez zboot (dziś wciąż
  ##      używamy stosu odziedziczonego po firmware),
  ##   2) obsługi jąder linkowanych pod adresy higher-half (wymaga własnych
  ##      tablic stron przed skokiem — patrz TODO w zbootpkg/elf),
  ##   3) właściwego skoku assemblerowego do `bootInfo.kernelEntry` zgodnie
  ##      z ABI System V AMD64 (RDI = wskaźnik na BootInfo) — UEFI używa
  ##      MS x64 ABI, więc konwencja wywołań zmienia się dokładnie w tym
  ##      miejscu i wymaga jawnego przełącznika (np. wstawki asm).
  while true:
    discard
