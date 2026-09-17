{.push checks: off, stackTrace: off, lineTrace: off.}

import zbootpkg/allocator
import zbootpkg/crt_shim
import zbootpkg/uefi_types
import zbootpkg/console
import zbootpkg/memory
import zbootpkg/filesystem
import zbootpkg/elf
import zbootpkg/graphics
import zbootpkg/paging
import zbootpkg/handoff

# Nim zawsze generuje i eksportuje `NimMain` (inicjalizacja alokatora ARC
# i uruchomienie kodu top-level modułów), normalnie wywoływane przez
# automatycznie wygenerowane `main()`. Ponieważ nadpisujemy punkt wejścia
# linkera na `efi_main` (patrz --passL w zenit_base.nimble), to
# auto-wygenerowane `main()` nigdy się nie wykona — MUSIMY więc wywołać
# NimMain() ręcznie, jako pierwszą instrukcję, inaczej środowisko
# uruchomieniowe Nima (potrzebne choćby do string/seq) nie zostanie
# zainicjalizowane.
proc NimMain() {.importc: "NimMain", cdecl.}

# Dolna granica identity-mappingu — nawet na maszynach z bardzo mało RAM-u
# (raportujących niski maxPhysicalAddress) chcemy mieć zapas na bufory
# zboot (mapa pamięci, BootInfo, stos) i same tablice stron.
const MinIdentityMapGiB = 4'u64
# Górna granica jako zabezpieczenie przed absurdalnie dużą liczbą wpisów
# w mapie pamięci (np. wadliwy firmware zgłaszający fikcyjny region przy
# adresie bliskim 2^64) prowadzącą do budowania identity-mappingu na
# nierealistyczną liczbę gigabajtów.
const MaxIdentityMapGiB = 512'u64
const GiB = 1024'u64 * 1024'u64 * 1024'u64

proc computeIdentityMapGiB(mmap: MemoryMapResult): uint64 =
  ## Wylicza, ile GiB niskiej pamięci fizycznej trzeba identity-mapować,
  ## na podstawie najwyższego adresu fizycznego zgłoszonego przez firmware
  ## w mapie pamięci (zaokrąglone w górę do pełnego GiB), przycięte do
  ## [MinIdentityMapGiB, MaxIdentityMapGiB].
  let maxAddr = mmap.maxPhysicalAddress()
  var gib = (maxAddr + GiB - 1'u64) div GiB # zaokrąglenie w górę
  if gib < MinIdentityMapGiB: gib = MinIdentityMapGiB
  if gib > MaxIdentityMapGiB: gib = MaxIdentityMapGiB
  gib

proc efiMain(imageHandle: EfiHandle, systemTable: ptr EfiSystemTable): EfiStatus {.exportc: "efi_main", cdecl.} =
  # Kolejność ma znaczenie: alokator musi być gotowy PRZED NimMain()
  # (która może alokować podczas inicjalizacji środowiska uruchomieniowego
  # ARC), a NimMain() musi zadziałać przed jakimkolwiek użyciem string/seq
  # (w tym pierwszym efiPrint poniżej).
  setAllocatorBootServices(systemTable.bootServices)
  initCrtShim()
  NimMain()

  setSystemTable(systemTable)
  discard systemTable.conOut.clearScreen(systemTable.conOut)

  efiPrint("zboot -- bootloader Zenit Linux (UEFI)\n")
  efiPrint("=========================================\n\n")

  let bs = systemTable.bootServices

  let kernel = loadKernelViaEsp(imageHandle, bs)
  if kernel.buffer == nil:
    panic("nie udalo sie wczytac obrazu jadra z ESP (\\ZENIT\\KERNEL.ELF)")

  let parsed = parseElfKernel(kernel.buffer, kernel.size)
  if not parsed.valid:
    panic("obraz jadra nie jest poprawnym plikiem ELF64")

  efiPrintHex("[zboot] punkt wejscia jadra", parsed.entryPoint)
  efiPrint("[zboot] liczba segmentow PT_LOAD: ")
  efiPrintUInt(uint64(parsed.segmentCount))
  efiPrint("\n")

  let mmap = getMemoryMap(bs)
  efiPrint("[zboot] dostepna pamiec (przyblizenie): ")
  efiPrintUInt(mmap.totalUsableBytes() div (1024*1024))
  efiPrint(" MiB\n")

  let identityMapGiB = computeIdentityMapGiB(mmap)
  efiPrint("[zboot] identity mapping: ")
  efiPrintUInt(identityMapGiB)
  efiPrint(" GiB (wyliczone z mapy pamieci)\n")

  let fb = getFramebufferInfo(bs)

  # Krok 1: przenieś segmenty PT_LOAD do spójnego regionu fizycznego,
  # zachowując ich względne odległości z linkowania (działa dla jąder
  # niskich i higher-half jednakowo).
  let (lowestVaddr, spanBytes) = computeSpan(parsed)
  if spanBytes == 0:
    panic("obraz jadra nie ma zadnych segmentow PT_LOAD do zaladowania")

  let kernelPhysBase = allocKernelPhysicalRegion(bs, spanBytes)
  copySegmentsToPhysical(kernel.buffer, parsed, kernelPhysBase, lowestVaddr)
  efiPrintHex("[zboot] jadro skopiowane pod adres fizyczny", kernelPhysBase)

  # Krok 2: zbuduj tablice stron ODWZOROWUJĄCE prawdziwy (higher-half lub
  # niski) adres wirtualny jądra na adres fizyczny z kroku 1, plus
  # identity mapping niskiej pamięci dla własnych struktur zboot.
  let pageTables = buildPageTables(bs, identityMapGiB, lowestVaddr, kernelPhysBase, parsed.segments, parsed.segmentCount)

  # Krok 3: dedykowany stos jądra z guard page'em POD nim (patrz
  # handoff.allocKernelStack / paging.punchGuardPage) — obie operacje
  # MUSZĄ nastąpić przed ExitBootServices (potrzebują `bs`).
  let (kernelStackTop, guardPhys) = allocKernelStack(bs)
  punchGuardPage(bs, pageTables.pml4Phys, guardPhys)
  efiPrintHex("[zboot] stos jadra (szczyt)", kernelStackTop)
  efiPrintHex("[zboot] guard page pod stosem jadra", guardPhys)

  efiPrint("[zboot] wychodze z Boot Services...\n")
  var exitStatus = bs.exitBootServices(imageHandle, mmap.mapKey)
  var finalMmap = mmap
  if exitStatus != StatusSuccess:
    # mapKey mógł się zdezaktualizować między GetMemoryMap a ExitBootServices
    # (np. przez alokacje wykonane w międzyczasie) — pobieramy mapę ponownie
    # i próbujemy jeszcze raz, zgodnie z zaleceniem specyfikacji UEFI.
    finalMmap = getMemoryMap(bs)
    exitStatus = bs.exitBootServices(imageHandle, finalMmap.mapKey)
    if exitStatus != StatusSuccess:
      panic("ExitBootServices() nie powiodlo sie nawet po ponownej probie")

  markBootServicesExited() # patrz zbootpkg/console -- odblokowuje `hlt` w panic()

  # Od tego momentu żadne usługi firmware (w tym konsola/efiPrint) nie są
  # już dostępne — stąd przełączenie tablic stron następuje dopiero teraz.
  activate(pageTables)

  var bootInfo = buildBootInfo(finalMmap, kernelPhysBase, parsed.entryPoint, fb)
  jumpToKernel(addr bootInfo, kernelStackTop)

  StatusSuccess

{.pop.}
