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

# GUID EFI_LOADED_IMAGE_PROTOCOL — pozwala odczytać, z JAKIEGO urządzenia
# firmware faktycznie wczytało TEN obraz zboot, zamiast zgadywać.
const EfiLoadedImageProtocolGuid = EfiGuid(
  data1: 0x5b1b31a1'u32, data2: 0x9562'u16, data3: 0x11d2'u16,
  data4: [0x8e'u8, 0x3f'u8, 0x00'u8, 0xa0'u8, 0xc9'u8, 0x69'u8, 0x72'u8, 0x3b'u8],
)

type
  # Tylko pola aż do DeviceHandle są nam potrzebne, ale MUSZĄ być
  # zadeklarowane w tej samej kolejności co w specyfikacji UEFI — layout
  # struktury C zależy od kolejności pól poprzedzających, nie tylko od
  # tego, którego pola faktycznie używamy (naturalne wyrównanie Nim dla
  # tej mieszanki uint32/wskaźników pokrywa się z C, tak samo jak przy
  # already istniejącym EfiMemoryDescriptor w uefi_types.nim).
  EfiLoadedImageProtocol {.pure, final.} = object
    revision:     uint32
    parentHandle: EfiHandle
    systemTable:  pointer
    deviceHandle*: EfiHandle
    filePath:      pointer
    reserved:      pointer

proc locateEspFileSystem(imageHandle: EfiHandle, bs: ptr EfiBootServices): ptr EfiSimpleFileSystemProtocol =
  ## Lokalizuje wolumin, z którego rzeczywiście wystartowało TO zboot:
  ## `HandleProtocol(imageHandle, LoadedImage)` daje `DeviceHandle`
  ## urządzenia źródłowego, a `HandleProtocol(DeviceHandle, SimpleFileSystem)`
  ## — jego system plików. To jest poprawne NIEZALEŻNIE od tego, ile
  ## wolumenów z systemem plików ma dana maszyna (dysk rozruchowy +
  ## dodatkowe dyski danych, wiele ESP przy multi-boot, itd.).
  ##
  ## Dopiero gdy się to nie uda (np. firmware nie eksponuje poprawnie
  ## `EFI_LOADED_IMAGE_PROTOCOL`), spadamy na poprzedni, uproszczony
  ## `LocateProtocol` — poprawny TYLKO, gdy w systemie jest dokładnie
  ## jeden wolumin z systemem plików, ale lepszy niż całkowita awaria.
  var loadedImage: ptr EfiLoadedImageProtocol
  var liGuid = EfiLoadedImageProtocolGuid
  var status = bs.handleProtocol(imageHandle, addr liGuid, cast[ptr pointer](addr loadedImage))

  if status == StatusSuccess and loadedImage != nil and loadedImage.deviceHandle != nil:
    var fs: ptr EfiSimpleFileSystemProtocol
    var fsGuid = EfiSimpleFileSystemProtocolGuid
    status = bs.handleProtocol(loadedImage.deviceHandle, addr fsGuid, cast[ptr pointer](addr fs))
    if status == StatusSuccess and fs != nil:
      return fs
    efiPrint("[zboot] DeviceHandle z LoadedImageProtocol bez Simple File System -- awaryjnie LocateProtocol\n")
  else:
    efiPrint("[zboot] EFI_LOADED_IMAGE_PROTOCOL niedostepny -- awaryjnie LocateProtocol\n")

  var fsFallback: ptr EfiSimpleFileSystemProtocol
  var fsGuid2 = EfiSimpleFileSystemProtocolGuid
  status = bs.locateProtocol(addr fsGuid2, nil, cast[ptr pointer](addr fsFallback))
  if status == StatusSuccess:
    return fsFallback
  nil

const MaxPathLen = 64
  ## Wystarczy z dużym zapasem dla `KernelPath` (17 znaków) i każdej
  ## rozsądnej przyszłej ścieżki na ESP.

proc asciiToUtf16Path(s: string, buf: var array[MaxPathLen, uint16]) =
  ## Konwertuje ASCII -> UTF-16 (CHAR16[]) do STAŁEGO bufora NA STOSIE --
  ## celowo BEZ `seq`/`newSeq` (ta sama klasa problemu co mutowalny
  ## `string`, patrz obszerna notatka przy `zbootpkg/console.efiPrintHex`:
  ## alokacje ARC-zarządzanych typów `seq`/`string` crashują twardym
  ## triple faultem w tym freestanding środowisku UEFI, zanim w ogóle
  ## dotrą do naszego własnego alokatora zbootpkg/allocator — błąd
  ## znaleziony przez rzeczywisty test w QEMU+OVMF). Ścieżka dłuższa niż
  ## `MaxPathLen - 1` zostaje po cichu obcięta zamiast przepełniać bufor.
  var i = 0
  for c in s:
    if i >= buf.len - 1: break
    buf[i] = uint16(ord(c))
    inc i
  buf[i] = 0'u16

proc loadKernelViaEsp*(imageHandle: EfiHandle, bs: ptr EfiBootServices): LoadedKernel =
  ## Lokalizuje wolumin ESP (patrz `locateEspFileSystem`) i czyta plik
  ## jądra do pamięci alokowanej dokładnie na jego rozmiar (odczytany
  ## przez GetInfo).
  result = LoadedKernel(buffer: nil, size: 0)

  let fs = locateEspFileSystem(imageHandle, bs)
  if fs == nil:
    efiPrint("[zboot] nie znaleziono Simple File System Protocol\n")
    return

  var root: ptr EfiFileProtocol
  var status = fs.openVolume(fs, addr root)
  if status != StatusSuccess:
    efiPrint("[zboot] openVolume() nie powiodlo sie\n")
    return

  var kernelFile: ptr EfiFileProtocol
  var pathBuf: array[MaxPathLen, uint16]
  asciiToUtf16Path(KernelPath, pathBuf)
  status = root.open(root, addr kernelFile, addr pathBuf[0], EfiFileModeRead, 0)
  if status != StatusSuccess:
    efiPrint("[zboot] nie znaleziono ")
    efiPrint(KernelPath)
    efiPrint("\n")
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

  efiPrint("[zboot] wczytano obraz jadra (")
  efiPrintUInt(readSize)
  efiPrint(" bajtow)\n")
  result = LoadedKernel(buffer: kernelBuffer, size: readSize)
