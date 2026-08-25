import ./console

const
  ElfMagic: array[4, uint8] = [0x7F'u8, 0x45'u8, 0x4C'u8, 0x46'u8] # 0x7F 'E' 'L' 'F'
  Elfclass64 = 2'u8
  PtLoad     = 1'u32

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
      ))

  if result.segments.len == 0:
    efiPrint("[zboot] ostrzezenie: brak segmentow PT_LOAD w obrazie jadra\n")

  result.valid = true

proc copySegmentsToMemory*(kernelBuffer: pointer, parsed: ParsedKernel) =
  ## Kopiuje każdy segment PT_LOAD z bufora pliku pod jego docelowy adres
  ## wirtualny (memSize może być większy niż fileSize — reszta to .bss,
  ## którą należy wyzerować).
  ##
  ## TODO: w trybie UEFI przed ExitBootServices adresy wirtualne = fizyczne
  ##       (identity mapping firmware), więc kopiowanie "pod vaddr" jest
  ##       tu bezpieczne tylko dla jąder linkowanych pod adresy zgodne z
  ##       tym założeniem (typowo >= 1 MiB, jak w tym projekcie). Jądra
  ##       linkowane pod wysokie adresy (higher-half) wymagają wcześniejszego
  ##       ustawienia własnych tablic stron — TODO w zbootpkg/handoff.
  for seg in parsed.segments:
    let src = cast[uint](kernelBuffer) + seg.fileOffset
    let dst = cast[ptr UncheckedArray[uint8]](seg.virtualAddr)
    let srcArr = cast[ptr UncheckedArray[uint8]](src)

    for i in 0 ..< int(seg.fileSize):
      dst[i] = srcArr[i]

    # Zerowanie .bss (część segmentu, która jest w pamięci, ale nie w pliku).
    for i in int(seg.fileSize) ..< int(seg.memSize):
      dst[i] = 0'u8
