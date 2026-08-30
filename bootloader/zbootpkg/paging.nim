import ./uefi_types
import ./console
import ./elf

const
  PageSize4K = 0x1000'u64
  PageSize2M = 0x200000'u64

  PtPresent    = 1'u64
  PtWritable   = 1'u64 shl 1
  PtHuge       = 1'u64 shl 7  # bit PS na poziomie PD -> strona 2 MiB zamiast wskaźnika na PT
  PtNoExecute  = 1'u64 shl 63 # wymaga włączonego EFER.NXE, patrz enableNoExecute()

  EferMsr = 0xC0000080'u32
  EferNxeBit = 1'u64 shl 11

type
  PageTables* = object
    pml4Phys*: uint64

proc enableNoExecute*() =
  ## Włącza NXE (bit 11) w rejestrze EFER (MSR 0xC0000080). Bez tego
  ## ustawienie bitu NX (63) we wpisie tablicy stron jest traktowane jako
  ## zarezerwowane i powoduje #GP zamiast po prostu zablokować wykonywanie
  ## kodu z danej strony.
  var lo, hi: uint32
  asm """
    rdmsr
    : "=a"(`lo`), "=d"(`hi`)
    : "c"(`EferMsr`)
  """
  var efer = (uint64(hi) shl 32) or uint64(lo)
  efer = efer or EferNxeBit
  lo = uint32(efer and 0xFFFFFFFF'u64)
  hi = uint32(efer shr 32)
  asm """
    wrmsr
    :
    : "c"(`EferMsr`), "a"(`lo`), "d"(`hi`)
  """

proc allocPageAligned(bs: ptr EfiBootServices, pages: uint64): uint64 =
  var address: uint64 = 0
  # AllocateAnyPages = 0, EfiLoaderData = 2
  let status = bs.allocatePages(0'u32, EfiMemoryType(2), pages.uint, addr address)
  if status != StatusSuccess:
    panic("nie udalo sie zaalokowac tablicy stron")

  # Świeże tablice muszą mieć wszystkie wpisy wyzerowane (not present),
  # inaczej odczytamy przypadkowe dane z niezainicjalizowanej pamięci.
  let p = cast[ptr UncheckedArray[uint8]](address)
  for i in 0 ..< int(pages * PageSize4K):
    p[i] = 0'u8
  address

proc pml4Index(v: uint64): int = int((v shr 39) and 0x1FF'u64)
proc pdptIndex(v: uint64): int = int((v shr 30) and 0x1FF'u64)
proc pdIndex(v: uint64): int  = int((v shr 21) and 0x1FF'u64)
proc ptIndex(v: uint64): int  = int((v shr 12) and 0x1FF'u64)

proc entriesOf(tableAddr: uint64): ptr UncheckedArray[uint64] =
  cast[ptr UncheckedArray[uint64]](tableAddr)

proc getOrCreateTable(bs: ptr EfiBootServices, parentEntries: ptr UncheckedArray[uint64],
                       index: int): uint64 =
  ## Zwraca fizyczny adres tabeli niższego poziomu wskazywanej przez
  ## `parentEntries[index]`, tworząc ją (i zerując), jeśli jeszcze nie istnieje.
  if (parentEntries[index] and PtPresent) == 0:
    let newTable = allocPageAligned(bs, 1)
    parentEntries[index] = (newTable and 0xFFFFFFFFFFFFF000'u64) or PtPresent or PtWritable
    newTable
  else:
    parentEntries[index] and 0xFFFFFFFFFFFFF000'u64

proc mapRegion2M(bs: ptr EfiBootServices, pml4Phys: uint64, virtStart: uint64,
                  physStart: uint64, sizeBytes: uint64) =
  ## Mapowanie "gruboziarniste" stronami 2 MiB, zawsze writable+executable
  ## — używane wyłącznie do identity-mappingu niskiej pamięci (bufory
  ## firmware/zboot), gdzie precyzyjne uprawnienia nie są istotne.
  var virt = virtStart and not (PageSize2M - 1)
  let virtEnd = virtStart + sizeBytes
  var phys = physStart and not (PageSize2M - 1)

  while virt < virtEnd:
    let pml4e = entriesOf(pml4Phys)
    let pdptPhys = getOrCreateTable(bs, pml4e, pml4Index(virt))
    let pdpte = entriesOf(pdptPhys)
    let pdPhys = getOrCreateTable(bs, pdpte, pdptIndex(virt))
    let pde = entriesOf(pdPhys)

    pde[pdIndex(virt)] = (phys and 0xFFFFFFFFFFE00000'u64) or PtPresent or PtWritable or PtHuge

    virt += PageSize2M
    phys += PageSize2M

proc pageFlags(segFlags: uint32): uint64 =
  ## Tłumaczy p_flags ELF (PF_R/PF_W/PF_X) na bity wpisu tablicy stron
  ## x86-64. PF_R jest ignorowane — na x86-64 strony są zawsze czytelne,
  ## jeśli są obecne (present); nie ma osobnego bitu "read-only disable".
  result = PtPresent
  if (segFlags and PfWrite) != 0:
    result = result or PtWritable
  if (segFlags and PfExecute) == 0:
    result = result or PtNoExecute # brak PF_X -> strona nie-wykonywalna

proc mapRegion4K(bs: ptr EfiBootServices, pml4Phys: uint64, virtStart: uint64,
                  physStart: uint64, sizeBytes: uint64, extraFlags: uint64) =
  var virt = virtStart and not (PageSize4K - 1)
  let virtEnd = virtStart + sizeBytes
  var phys = physStart and not (PageSize4K - 1)

  while virt < virtEnd:
    let pml4e = entriesOf(pml4Phys)
    let pdptPhys = getOrCreateTable(bs, pml4e, pml4Index(virt))
    let pdpte = entriesOf(pdptPhys)
    let pdPhys = getOrCreateTable(bs, pdpte, pdptIndex(virt))
    let pde = entriesOf(pdPhys)
    let ptPhys = getOrCreateTable(bs, pde, pdIndex(virt))
    let pte = entriesOf(ptPhys)

    pte[ptIndex(virt)] = (phys and 0xFFFFFFFFFFFFF000'u64) or extraFlags

    virt += PageSize4K
    phys += PageSize4K

proc mapKernelSegments(bs: ptr EfiBootServices, pml4Phys: uint64,
                        segments: seq[LoadSegment], kernelVirtBase: uint64,
                        kernelPhysBase: uint64) =
  ## Mapuje KAŻDY segment PT_LOAD osobno, stronami 4 KiB, z uprawnieniami
  ## wynikającymi z jego własnych p_flags — np. sekcja .text dostaje
  ## R+X (bez W), .data dostaje R+W (bez X), zamiast jednego mapowania
  ## R+W+X dla całego obszaru jądra.
  for seg in segments:
    let segVirt = seg.virtualAddr
    let segPhys = kernelPhysBase + (seg.virtualAddr - kernelVirtBase)
    # Zaokrąglenie w górę do granicy strony 4 KiB, żeby objąć całe memSize
    # (w tym .bss, które jest tylko w pamięci, nie w pliku).
    let sizeRounded = (seg.memSize + PageSize4K - 1) and not (PageSize4K - 1)
    let flags = pageFlags(seg.flags)
    mapRegion4K(bs, pml4Phys, segVirt, segPhys, sizeRounded, flags)

proc buildPageTables*(bs: ptr EfiBootServices, identityMapGiB: uint64,
                       kernelVirtBase: uint64, kernelPhysBase: uint64,
                       segments: seq[LoadSegment]): PageTables =
  ## Buduje kompletny zestaw tablic stron obejmujący:
  ##   1) identity mapping niskiej pamięci (0 .. identityMapGiB GiB),
  ##      stronami 2 MiB — dla buforów zboot (mapa pamięci, BootInfo, stos),
  ##   2) mapowanie KAŻDEGO segmentu PT_LOAD jądra osobno, stronami 4 KiB,
  ##      z uprawnieniami R/W/X odpowiadającymi jego p_flags.
  ##
  ## TODO: `identityMapGiB` jest dziś stałą przekazywaną z zboot.nim
  ## (4 GiB); docelowo powinno to być wyliczone z najwyższego adresu
  ## fizycznego w mapie pamięci (zbootpkg/memory), żeby nie zakładać
  ## sztywnego rozmiaru RAM-u.
  enableNoExecute()

  let pml4Phys = allocPageAligned(bs, 1)

  mapRegion2M(bs, pml4Phys, 0'u64, 0'u64, identityMapGiB * 1024'u64 * 1024'u64 * 1024'u64)
  mapKernelSegments(bs, pml4Phys, segments, kernelVirtBase, kernelPhysBase)

  PageTables(pml4Phys: pml4Phys)

proc activate*(pt: PageTables) =
  ## Ładuje CR3 nowymi tablicami stron. UEFI na x86_64 już działa w long
  ## mode z włączonym stronicowaniem (wymóg specyfikacji), więc samo
  ## przeładowanie CR3 wystarcza — nie trzeba ponownie ustawiać PAE/LME/PG.
  ## MUSI być wywołane DOPIERO PO ExitBootServices (przed tym firmware
  ## polega na własnych tablicach stron przy każdym wywołaniu Boot/Runtime
  ## Services).
  let pml4 = pt.pml4Phys
  asm """
    mov cr3, %0
    :
    : "r"(`pml4`)
  """
