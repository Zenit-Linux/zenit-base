import zbootpkg/uefi_types
import zbootpkg/console
import zbootpkg/memory
import zbootpkg/filesystem
import zbootpkg/elf
import zbootpkg/handoff

proc efiMain(imageHandle: EfiHandle, systemTable: ptr EfiSystemTable): EfiStatus {.exportc: "efi_main", cdecl.} =
  setSystemTable(systemTable)
  discard systemTable.conOut.clearScreen(systemTable.conOut)

  efiPrint("zboot -- bootloader Zenith Linux (UEFI)\n")
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

  copySegmentsToMemory(kernel.buffer, parsed)

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

  var bootInfo = buildBootInfo(finalMmap, cast[uint64](kernel.buffer), parsed.entryPoint)
  jumpToKernel(addr bootInfo)

  StatusSuccess

{.pop.}
