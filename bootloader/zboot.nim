{.push checks: off, stackTrace: off, lineTrace: off.}

import zbootpkg/allocator
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

# Ile GiB niskiej pamięci fizycznej identity-mapujemy w nowych tablicach
# stron — musi pokrywać wszystkie bufory zboot (mapa pamięci, BootInfo,
# stos) oraz strukturę samych tablic stron. TODO: wyliczać dynamicznie
# z mapy pamięci zamiast stałej.
const IdentityMapGiB = 4'u64

proc efiMain(imageHandle: EfiHandle, systemTable: ptr EfiSystemTable): EfiStatus {.exportc: "efi_main", cdecl.} =
  # Kolejność ma znaczenie: alokator musi być gotowy PRZED NimMain()
  # (która może alokować podczas inicjalizacji środowiska uruchomieniowego
  # ARC), a NimMain() musi zadziałać przed jakimkolwiek użyciem string/seq
  # (w tym pierwszym efiPrint poniżej).
  setAllocatorBootServices(systemTable.bootServices)
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
  efiPrint("[zboot] liczba segmentow PT_LOAD: " & $parsed.segments.len & "\n")

  let mmap = getMemoryMap(bs)
  efiPrint("[zboot] dostepna pamiec (przyblizenie): " & $(mmap.totalUsableBytes() div (1024*1024)) & " MiB\n")

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
  let pageTables = buildPageTables(bs, IdentityMapGiB, lowestVaddr, kernelPhysBase, parsed.segments)

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

  # Od tego momentu żadne usługi firmware (w tym konsola/efiPrint) nie są
  # już dostępne — stąd przełączenie tablic stron następuje dopiero teraz.
  activate(pageTables)

  var bootInfo = buildBootInfo(finalMmap, kernelPhysBase, parsed.entryPoint, fb)
  jumpToKernel(addr bootInfo)

  StatusSuccess

{.pop.}
