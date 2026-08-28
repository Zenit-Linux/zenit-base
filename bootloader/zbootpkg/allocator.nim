import ./uefi_types

{.push stackTrace: off, checks: off.}

var gAllocBootServices: ptr EfiBootServices

proc setAllocatorBootServices*(bs: ptr EfiBootServices) =
  ## MUSI zostać wywołane jako pierwsza rzecz w efiMain, zanim jakikolwiek
  ## kod (włącznie z NimMain(), patrz zboot.nim) spróbuje cokolwiek
  ## zaalokować — inaczej malloc() poniżej zwróci nil.
  gAllocBootServices = bs

const SizePrefixBytes = sizeof(uint)

proc zenitMalloc(size: csize_t): pointer {.exportc: "malloc", cdecl.} =
  if gAllocBootServices == nil or size == 0:
    return nil

  let totalSize = uint(size) + uint(SizePrefixBytes)
  var raw: pointer
  let status = gAllocBootServices.allocatePool(2'u32, totalSize, addr raw) # 2 = EfiLoaderData
  if status != StatusSuccess or raw == nil:
    return nil

  cast[ptr uint](raw)[] = uint(size)
  cast[pointer](cast[uint](raw) + uint(SizePrefixBytes))

proc zenitFree(p: pointer) {.exportc: "free", cdecl.} =
  if p == nil or gAllocBootServices == nil:
    return
  let raw = cast[pointer](cast[uint](p) - uint(SizePrefixBytes))
  discard gAllocBootServices.freePool(raw)

proc zenitRealloc(p: pointer, newSize: csize_t): pointer {.exportc: "realloc", cdecl.} =
  if p == nil:
    return zenitMalloc(newSize)
  if newSize == 0:
    zenitFree(p)
    return nil

  let rawOld = cast[pointer](cast[uint](p) - uint(SizePrefixBytes))
  let oldSize = cast[ptr uint](rawOld)[]

  let newP = zenitMalloc(newSize)
  if newP == nil:
    return nil

  let copySize = min(oldSize, uint(newSize))
  copyMem(newP, p, int(copySize))
  zenitFree(p)
  newP

{.pop.}
