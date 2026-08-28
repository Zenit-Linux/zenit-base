import ./console
import ./uefi_types

const
  ElfMagic: array[4, uint8] = [0x7F'u8, 0x45'u8, 0x4C'u8, 0x46'u8] # 0x7F 'E' 'L' 'F'
  Elfclass64 = 2'u8
  PtLoad     = 1'u32

  # Wartości p_flags z nagłówka programu (ELF), używane do ustawienia
  # właściwych uprawnień strony (R/W/X) w zbootpkg/paging.
  PfExecute* = 1'u32
  PfWrite*   = 2'u32
  PfRead*    = 4'u32

type
  Elf64Ehdr {.packed.} = object
    magic:      array[4, uint8]
    class:      uint8
    data:       uint8
    version:    uint8
    osabi:      uint8
    abiversion: uint8
    pad:        array[7, uint8]
    kind:       uint16
    machine:    uint16
    versionL:   uint32
    entry:      uint64
    phoff:      uint64
    shoff:      uint64
    flags:      uint32
    ehsize:     uint16
    phentsize:  uint16
    phnum:      uint16
    shentsize:  uint16
    shnum:      uint16
    shstrndx:   uint16

  Elf64Phdr {.packed.} = object
    kind:   uint32
    flags:  uint32
    offset: uint64
    vaddr:  uint64
    paddr:  uint64
    filesz: uint64
    memsz:  uint64
    align:  uint64

  LoadSegment* = object
    fileOffset*: uint64
    virtualAddr*: uint64
    fileSize*:   uint64
    memSize*:    uint64
    flags*:      uint32 # p_flags z nagłówka programu: PF_X=1, PF_W=2, PF_R=4

  ParsedKernel* = object
    valid*:      bool
    entryPoint*: uint64
    segments*:   seq[LoadSegment]

proc parseElfKernel*(buffer: pointer, bufferLen: uint): ParsedKernel =
  result = ParsedKernel(valid: false, entryPoint: 0, segments: @[])

  if bufferLen < sizeof(Elf64Ehdr).uint:
    efiPrint("[zboot] obraz jadra za maly, aby zawierac naglowek ELF64\n")
    return

  let ehdr = cast[ptr Elf64Ehdr](buffer)

  for i in 0 ..< 4:
    if ehdr.magic[i] != ElfMagic[i]:
      efiPrint("[zboot] nieprawidlowe magic ELF w obrazie jadra\n")
      return

  if ehdr.class != Elfclass64:
    efiPrint("[zboot] obraz jadra nie jest ELF64 (wymagany dla x86_64)\n")
    return

  result.entryPoint = ehdr.entry

  let phTable = cast[uint](buffer) + ehdr.phoff.uint
  for i in 0 ..< int(ehdr.phnum):
    let phdr = cast[ptr Elf64Phdr](phTable + uint(i) * ehdr.phentsize.uint)
    if phdr.kind == PtLoad:
      result.segments.add(LoadSegment(
        fileOffset: phdr.offset,
        virtualAddr: phdr.vaddr,
        fileSize: phdr.filesz,
        memSize: phdr.memsz,
        flags: phdr.flags,
      ))

  if result.segments.len == 0:
    efiPrint("[zboot] ostrzezenie: brak segmentow PT_LOAD w obrazie jadra\n")

  result.valid = true

proc computeSpan*(parsed: ParsedKernel): tuple[lowestVaddr: uint64, spanBytes: uint64] =
  ## Wyznacza najniższy adres wirtualny spośród segmentów PT_LOAD oraz
  ## całkowitą rozpiętość pamięci, jaką segmenty zajmują (od najniższego
  ## adresu do końca najwyższego). Potrzebne, żeby zaalokować JEDEN spójny
  ## region fizyczny i zbudować dla niego tablice stron — działa zarówno
  ## dla jąder linkowanych nisko (np. 0x100000), jak i higher-half
  ## (np. 0xFFFFFFFF80000000).
  if parsed.segments.len == 0:
    return (0'u64, 0'u64)

  var lowest = uint64.high
  var highest = 0'u64
  for seg in parsed.segments:
    if seg.virtualAddr < lowest:
      lowest = seg.virtualAddr
    let segEnd = seg.virtualAddr + seg.memSize
    if segEnd > highest:
      highest = segEnd

  (lowest, highest - lowest)

proc allocKernelPhysicalRegion*(bs: ptr EfiBootServices, spanBytes: uint64): uint64 =
  ## Alokuje spójny region fizycznej pamięci (wyrównany do stron 4 KiB)
  ## na tyle duży, by pomieścić wszystkie segmenty PT_LOAD w ich
  ## względnych odległościach od najniższego adresu wirtualnego.
  const pageSize = 4096'u64
  let pages = (spanBytes + pageSize - 1) div pageSize
  var address: uint64 = 0
  # AllocateAnyPages = 0, EfiLoaderData = 2
  let status = bs.allocatePages(0'u32, 2'u32, pages, addr address)
  if status != StatusSuccess:
    panic("nie udalo sie zaalokowac fizycznego regionu na jadro (" & $spanBytes & " bajtow)")
  address

proc copySegmentsToPhysical*(kernelBuffer: pointer, parsed: ParsedKernel,
                              physBase: uint64, lowestVaddr: uint64) =
  ## Kopiuje każdy segment PT_LOAD z bufora pliku pod adres fizyczny
  ## `physBase + (vaddr - lowestVaddr)` — czyli zachowuje względne
  ## odległości między segmentami z linkowania, ale umieszcza całość pod
  ## adresem fizycznym wybranym przez bootloader, niezależnie od tego, czy
  ## oryginalne adresy wirtualne są niskie czy higher-half. Odwzorowanie
  ## adresu wirtualnego z powrotem na ten adres fizyczny jest zadaniem
  ## tablic stron budowanych w zbootpkg/paging.nim.
  for seg in parsed.segments:
    let src = cast[uint](kernelBuffer) + seg.fileOffset
    let destPhys = physBase + (seg.virtualAddr - lowestVaddr)
    let dst = cast[ptr UncheckedArray[uint8]](destPhys)
    let srcArr = cast[ptr UncheckedArray[uint8]](src)

    for i in 0 ..< int(seg.fileSize):
      dst[i] = srcArr[i]

    for i in int(seg.fileSize) ..< int(seg.memSize):
      dst[i] = 0'u8

proc copySegmentsToMemory*(kernelBuffer: pointer, parsed: ParsedKernel) =
  ## WARIANT UPROSZCZONY (zachowany dla zgodności): kopiuje segmenty
  ## bezpośrednio pod ich adres wirtualny, zakładając identity mapping
  ## (vaddr == paddr). Poprawne TYLKO dla jąder linkowanych nisko w
  ## pamięci. Główna ścieżka w zboot.nim używa teraz
  ## `copySegmentsToPhysical` + `zbootpkg/paging` zamiast tej procedury,
  ## właśnie po to, by obsłużyć również jądra higher-half.
  for seg in parsed.segments:
    let src = cast[uint](kernelBuffer) + seg.fileOffset
    let dst = cast[ptr UncheckedArray[uint8]](seg.virtualAddr)
    let srcArr = cast[ptr UncheckedArray[uint8]](src)

    for i in 0 ..< int(seg.fileSize):
      dst[i] = srcArr[i]

    # Zerowanie .bss (część segmentu, która jest w pamięci, ale nie w pliku).
    for i in int(seg.fileSize) ..< int(seg.memSize):
      dst[i] = 0'u8
