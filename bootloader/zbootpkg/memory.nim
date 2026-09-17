import ./uefi_types
import ./console

type
  MemoryMapResult* = object
    buffer*:            pointer
    size*:               uint
    mapKey*:              uint
    descriptorSize*:       uint
    descriptorVersion*:     uint32

proc getMemoryMap*(bs: ptr EfiBootServices): MemoryMapResult =
  var size: uint = 0
  var mapKey, descSize: uint
  var descVersion: uint32
  var dummy: EfiMemoryDescriptor

  # Pierwsze wywołanie z rozmiarem 0 celowo kończy się błędem — zwraca
  # w `size` faktycznie wymagany rozmiar bufora.
  discard bs.getMemoryMap(addr size, addr dummy, addr mapKey, addr descSize, addr descVersion)

  # Zapas na dodatkowe wpisy, które mogą powstać przy alokacji poniższego
  # bufora (sama AllocatePool też zmienia mapę pamięci).
  size += 2 * descSize.max(sizeof(EfiMemoryDescriptor).uint)

  var buffer: pointer
  var status = bs.allocatePool(2'u32, size, addr buffer) # 2 = EfiLoaderData
  if status != StatusSuccess:
    panic("nie udalo sie zaalokowac bufora na mape pamieci")

  status = bs.getMemoryMap(
    addr size,
    cast[ptr EfiMemoryDescriptor](buffer),
    addr mapKey,
    addr descSize,
    addr descVersion,
  )
  if status != StatusSuccess:
    panic("GetMemoryMap() nie powiodlo sie nawet po alokacji poprawnego bufora")

  result = MemoryMapResult(
    buffer: buffer,
    size: size,
    mapKey: mapKey,
    descriptorSize: descSize,
    descriptorVersion: descVersion,
  )

proc regionCount*(m: MemoryMapResult): int =
  ## Liczba wpisów (deskryptorów regionów) w mapie pamięci.
  if m.descriptorSize == 0: return 0
  int(m.size div m.descriptorSize)

proc regionAt*(m: MemoryMapResult, index: int): ptr EfiMemoryDescriptor =
  cast[ptr EfiMemoryDescriptor](cast[uint](m.buffer) + uint(index) * m.descriptorSize)

const
  # Wartości typów regionów wg specyfikacji UEFI (EFI_MEMORY_TYPE),
  # nazwane tu jawnie zamiast rozrzuconych po kodzie liczb "7", "3" itd.
  EfiReservedMemoryType      = 0'u32
  EfiLoaderCode              = 1'u32
  EfiLoaderData              = 2'u32
  EfiBootServicesCode        = 3'u32
  EfiBootServicesData        = 4'u32
  EfiRuntimeServicesCode     = 5'u32
  EfiRuntimeServicesData     = 6'u32
  EfiConventionalMemory      = 7'u32
  EfiUnusableMemory          = 8'u32
  EfiACPIReclaimMemory       = 9'u32
  EfiACPIMemoryNVS           = 10'u32
  EfiMemoryMappedIO          = 11'u32
  EfiMemoryMappedIOPortSpace = 12'u32
  EfiPalCode                 = 13'u32
  EfiPersistentMemory        = 14'u32

proc isUsableAfterExit(kind: uint32): bool =
  ## Regiony, które firmware zwraca systemowi operacyjnemu PO
  ## `ExitBootServices()`: nie tylko `EfiConventionalMemory` (już wolna),
  ## ale też pamięć samego środowiska boot services (kod/dane firmware +
  ## KOD/DANE ŁADUJĄCEGO, czyli zboot) — po `ExitBootServices` firmware
  ## przestaje z niej korzystać i staje się ona zwykłą, wolną pamięcią.
  ## `EfiRuntimeServices*`, ACPI NVS i MMIO NIE są tu liczone: te firmware
  ## zachowuje dla siebie (runtime services) albo w ogóle nie są pamięcią
  ## operacyjną (MMIO).
  kind in [EfiLoaderCode, EfiLoaderData, EfiBootServicesCode,
           EfiBootServicesData, EfiConventionalMemory]

proc totalUsableBytes*(m: MemoryMapResult): uint64 =
  ## Suma pamięci w regionach, które stają się dostępne dla systemu po
  ## `ExitBootServices()` — pełna klasyfikacja wg `isUsableAfterExit`
  ## (poprzednio liczony był tylko typ `EfiConventionalMemory`, co
  ## zaniżało wynik o pamięć samych boot services i obrazu zboot).
  result = 0
  for i in 0 ..< m.regionCount():
    let desc = m.regionAt(i)
    if isUsableAfterExit(desc.kind):
      result += desc.numberOfPages * 4096'u64

proc maxPhysicalAddress*(m: MemoryMapResult): uint64 =
  ## Najwyższy adres fizyczny (wyłącznie górna granica) wystąpujący w
  ## KTÓRYMKOLWIEK regionie mapy pamięci, niezależnie od jego typu —
  ## używane do wyliczenia, ile pamięci trzeba objąć identity-mappingiem
  ## budowanym w zbootpkg/paging, zamiast zakładać sztywny rozmiar RAM-u.
  ## Regiony zarezerwowane/MMIO też się liczą: identity map musi pokrywać
  ## całą przestrzeń adresową, z której zboot mógłby czegoś odczytać, a
  ## nie tylko pamięć oznaczoną jako "dostępna".
  result = 0
  for i in 0 ..< m.regionCount():
    let desc = m.regionAt(i)
    let regionEnd = desc.physicalStart + desc.numberOfPages * 4096'u64
    if regionEnd > result:
      result = regionEnd
