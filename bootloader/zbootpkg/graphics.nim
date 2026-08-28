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
    queryMode:  pointer
    setMode:    pointer
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

proc getFramebufferInfo*(bs: ptr EfiBootServices): FramebufferInfo =
  result = FramebufferInfo(present: false)

  var gop: ptr EfiGraphicsOutputProtocol
  var guid = EfiGraphicsOutputProtocolGuid
  let status = bs.locateProtocol(addr guid, nil, cast[ptr pointer](addr gop))
  if status != StatusSuccess or gop == nil:
    efiPrint("[zboot] GOP niedostepny — jadro bedzie musialo uzyc trybu tekstowego\n")
    return

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

  efiPrint("[zboot] framebuffer: " & $result.width & "x" & $result.height &
            " @ 0x")
  efiPrintHex("baza", result.base)

  # TODO: iteracja po dostępnych trybach (QueryMode dla i in 0..<maxMode) i
  # wybór najwyższej rozdzielczości przez SetMode zamiast akceptowania
  # trybu ustawionego domyślnie przez firmware.
