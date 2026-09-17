import ./uefi_types
import ./console

const EfiGraphicsOutputProtocolGuid = EfiGuid(
  data1: 0x9042a9de'u32, data2: 0x23dc'u16, data3: 0x4a38'u16,
  data4: [0x96'u8, 0xfb'u8, 0x7a'u8, 0xde'u8, 0xd0'u8, 0x80'u8, 0x51'u8, 0x6a'u8],
)

type
  EfiPixelFormat = uint32 # 0 = RGB, 1 = BGR, 2 = maski bitowe, 3 = tylko blt

  EfiPixelBitmask {.packed.} = object
    redMask, greenMask, blueMask, reservedMask: uint32

  EfiGraphicsOutputModeInformation {.packed.} = object
    version:              uint32
    horizontalResolution: uint32
    verticalResolution:   uint32
    pixelFormat:          EfiPixelFormat
    pixelInformation:     EfiPixelBitmask
    pixelsPerScanLine:    uint32

  EfiGraphicsOutputProtocolMode = object
    maxMode*:          uint32
    mode*:             uint32
    info*:             ptr EfiGraphicsOutputModeInformation
    sizeOfInfo*:       uint
    frameBufferBase*:  uint64
    frameBufferSize*:  uint

  EfiGraphicsOutputProtocol = object
    queryMode*: proc(this: ptr EfiGraphicsOutputProtocol, modeNumber: uint32,
                      sizeOfInfo: ptr uint,
                      info: ptr ptr EfiGraphicsOutputModeInformation): EfiStatus {.cdecl.}
    setMode*:   proc(this: ptr EfiGraphicsOutputProtocol, modeNumber: uint32): EfiStatus {.cdecl.}
    blt:        pointer
    mode*:      ptr EfiGraphicsOutputProtocolMode

  FramebufferInfo* = object
    present*:       bool
    base*:          uint64
    size*:          uint64
    width*:         uint32
    height*:        uint32
    pixelsPerLine*: uint32
    bgr*:           bool # true, jeśli format pikseli to BGR zamiast RGB

proc selectHighestResolutionMode(gop: ptr EfiGraphicsOutputProtocol) =
  ## Iteruje przez WSZYSTKIE tryby zgłoszone przez GOP (0 ..< maxMode) przez
  ## QueryMode, wybiera ten o największej liczbie pikseli (szerokość *
  ## wysokość) i przełącza się na niego przez SetMode — zamiast akceptować
  ## tryb ustawiony domyślnie przez firmware (często niska rozdzielczość
  ## "bezpieczna" dla ekranów tekstowych/awaryjnych).
  ##
  ## Best-effort: jeśli QueryMode/SetMode zawiodą dla wszystkich trybów
  ## (albo gop.mode.maxMode == 0), po prostu zostajemy przy trybie
  ## bieżącym — brak framebufferu w wysokiej rozdzielczości nie jest
  ## powodem do panic(), jądro i tak dostaje FramebufferInfo z tego, co
  ## faktycznie jest aktywne w momencie odczytu.
  if gop.queryMode == nil or gop.setMode == nil or gop.mode == nil:
    return

  let maxMode = gop.mode.maxMode
  if maxMode == 0:
    return

  var bestMode: uint32 = gop.mode.mode
  var bestPixels: uint64 = 0
  if gop.mode.info != nil:
    bestPixels = uint64(gop.mode.info.horizontalResolution) *
                 uint64(gop.mode.info.verticalResolution)

  for modeNumber in 0'u32 ..< maxMode:
    var infoSize: uint = 0
    var info: ptr EfiGraphicsOutputModeInformation = nil
    let status = gop.queryMode(gop, modeNumber, addr infoSize, addr info)
    if status != StatusSuccess or info == nil:
      continue

    let pixels = uint64(info.horizontalResolution) * uint64(info.verticalResolution)
    if pixels > bestPixels:
      bestPixels = pixels
      bestMode = modeNumber

  if bestMode != gop.mode.mode:
    let status = gop.setMode(gop, bestMode)
    if status != StatusSuccess:
      efiPrint("[zboot] SetMode() na tryb o najwyzszej rozdzielczosci nie powiodlo sie — zostaje biezacy tryb\n")

proc getFramebufferInfo*(bs: ptr EfiBootServices): FramebufferInfo =
  result = FramebufferInfo(present: false)

  var gop: ptr EfiGraphicsOutputProtocol
  var guid = EfiGraphicsOutputProtocolGuid
  let status = bs.locateProtocol(addr guid, nil, cast[ptr pointer](addr gop))
  if status != StatusSuccess or gop == nil:
    efiPrint("[zboot] GOP niedostepny — jadro bedzie musialo uzyc trybu tekstowego\n")
    return

  selectHighestResolutionMode(gop)

  let mode = gop.mode
  if mode == nil or mode.info == nil:
    efiPrint("[zboot] GOP zwrocil pusty tryb — pomijam framebuffer\n")
    return

  result = FramebufferInfo(
    present: true,
    base: mode.frameBufferBase,
    size: mode.frameBufferSize.uint64,
    width: mode.info.horizontalResolution,
    height: mode.info.verticalResolution,
    pixelsPerLine: mode.info.pixelsPerScanLine,
    bgr: mode.info.pixelFormat == 1'u32,
  )

  efiPrint("[zboot] framebuffer: ")
  efiPrintUInt(uint64(result.width))
  efiPrint("x")
  efiPrintUInt(uint64(result.height))
  efiPrint(" @ ")
  efiPrintHex("baza", result.base)
