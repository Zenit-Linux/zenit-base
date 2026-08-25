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

proc totalUsableBytes*(m: MemoryMapResult): uint64 =
  ## Suma pamięci w regionach typu "dostępna" (EfiConventionalMemory = 7).
  ## TODO: pełna klasyfikacja wg wszystkich typów EFI_MEMORY_TYPE — dziś
  ## liczymy tylko typ 7, co wystarcza jako przybliżenie do celów logowania.
  result = 0
  for i in 0 ..< m.regionCount():
    let desc = m.regionAt(i)
    if desc.kind == 7'u32:
      result += desc.numberOfPages * 4096'u64
