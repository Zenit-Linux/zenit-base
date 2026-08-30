import ./uefi_types
import ./console

const KernelPath = "\\ZENIT\\KERNEL.ELF"

# GUID EFI_FILE_INFO, wymagany do GetInfo() w celu poznania rozmiaru pliku.
const EfiFileInfoGuid = EfiGuid(
  data1: 0x09576e92'u32, data2: 0x6d3f'u16, data3: 0x11d2'u16,
  data4: [0x8e'u8, 0x39'u8, 0x00'u8, 0xa0'u8, 0xc9'u8, 0x69'u8, 0x72'u8, 0x3b'u8],
)

type
  # Tylko pola potrzebne do odczytania rozmiaru pliku — EFI_FILE_INFO ma
  # więcej pól (znaczniki czasu, atrybuty, nazwa), które tu pomijamy.
  EfiFileInfoHeader {.packed.} = object
    size:        uint64
    fileSize:    uint64
    physicalSize: uint64

type
  LoadedKernel* = object
    buffer*: pointer
    size*:   uint

proc asciiToUtf16Path(s: string): seq[uint16] =
  result = newSeq[uint16](s.len + 1)
  for i, c in s:
    result[i] = uint16(ord(c))
  result[s.len] = 0'u16

proc loadKernelViaEsp*(imageHandle: EfiHandle, bs: ptr EfiBootServices): LoadedKernel =
  ## Lokalizuje wolumin ESP i czyta plik jądra do pamięci alokowanej
  ## dokładnie na jego rozmiar (odczytany przez GetInfo).
  ##
  ## TODO: pobranie EFI_LOADED_IMAGE_PROTOCOL, aby uzyskać właściwy
  ## DeviceHandle (obecnie zakładamy uproszczony LocateProtocol, co
  ## działa tylko gdy w systemie jest jeden wolumin FS).
  result = LoadedKernel(buffer: nil, size: 0)

  var fs: ptr EfiSimpleFileSystemProtocol
  var fsGuid = EfiSimpleFileSystemProtocolGuid
  var status = bs.locateProtocol(addr fsGuid, nil, cast[ptr pointer](addr fs))
  if status != StatusSuccess:
    efiPrint("[zboot] nie znaleziono Simple File System Protocol\n")
    return

  var root: ptr EfiFileProtocol
  status = fs.openVolume(fs, addr root)
  if status != StatusSuccess:
    efiPrint("[zboot] openVolume() nie powiodlo sie\n")
    return

  var kernelFile: ptr EfiFileProtocol
  var pathBuf = asciiToUtf16Path(KernelPath)
  status = root.open(root, addr kernelFile, addr pathBuf[0], EfiFileModeRead, 0)
  if status != StatusSuccess:
    efiPrint("[zboot] nie znaleziono " & KernelPath & "\n")
    return

  # Krok 1: GetInfo z zerowym buforem — podobnie jak przy GetMemoryMap,
  # zwraca wymagany rozmiar w bufferSize zamiast danych.
  var infoGuid = EfiFileInfoGuid
  var infoSize: uint = 0
  discard kernelFile.getInfo(kernelFile, addr infoGuid, addr infoSize, nil)

  var infoBuffer: pointer
  status = bs.allocatePool(2'u32, infoSize, addr infoBuffer)
  if status != StatusSuccess:
    efiPrint("[zboot] nie udalo sie zaalokowac bufora EFI_FILE_INFO\n")
    discard kernelFile.close(kernelFile)
    return

  status = kernelFile.getInfo(kernelFile, addr infoGuid, addr infoSize, infoBuffer)
  if status != StatusSuccess:
    efiPrint("[zboot] GetInfo() nie powiodlo sie dla obrazu jadra\n")
    discard kernelFile.close(kernelFile)
    return

  let fileSize = cast[ptr EfiFileInfoHeader](infoBuffer).fileSize

  # Krok 2: alokacja bufora dokładnie na rozmiar pliku i właściwy odczyt.
  var kernelBuffer: pointer
  status = bs.allocatePool(EfiMemoryType(2), fileSize.uint, addr kernelBuffer)
  if status != StatusSuccess:
    efiPrint("[zboot] nie udalo sie zaalokowac bufora na obraz jadra\n")
    discard kernelFile.close(kernelFile)
    return

  var readSize: uint = fileSize.uint
  status = kernelFile.read(kernelFile, addr readSize, kernelBuffer)
  discard kernelFile.close(kernelFile)

  if status != StatusSuccess:
    efiPrint("[zboot] blad odczytu obrazu jadra\n")
    return

  efiPrint("[zboot] wczytano obraz jadra (" & $readSize & " bajtow)\n")
  result = LoadedKernel(buffer: kernelBuffer, size: readSize)
