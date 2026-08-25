{.push checks: off, stackTrace: off, lineTrace: off.}

type
  EfiStatus* = uint
  EfiHandle* = pointer
  EfiEvent*  = pointer
  EfiTpl*    = uint

  EfiGuid* = object
    data1*: uint32
    data2*: uint16
    data3*: uint16
    data4*: array[8, uint8]

  EfiMemoryDescriptor* = object
    kind*:          uint32
    physicalStart*:  uint64
    virtualStart*:   uint64
    numberOfPages*:  uint64
    attribute*:      uint64

  EfiTextOutputProtocol* = object
    reset*:            pointer
    outputString*:     proc(this: ptr EfiTextOutputProtocol, str: ptr uint16): EfiStatus {.cdecl.}
    testString*:       pointer
    queryMode*:        pointer
    setMode*:          pointer
    setAttribute*:     pointer
    clearScreen*:      proc(this: ptr EfiTextOutputProtocol): EfiStatus {.cdecl.}
    setCursorPosition*: pointer
    enableCursor*:     pointer
    mode*:             pointer

  EfiAllocateType*     = uint32
  EfiMemoryType*       = uint32
  EfiLocateSearchType* = uint32

  EfiBootServices* = object
    hdr*: array[3, uint64] # EFI_TABLE_HEADER

    raiseTpl*:   pointer
    restoreTpl*: pointer

    allocatePages*: pointer
    freePages*:     pointer
    getMemoryMap*:  proc(memoryMapSize: ptr uint, memoryMap: ptr EfiMemoryDescriptor,
                          mapKey: ptr uint, descriptorSize: ptr uint,
                          descriptorVersion: ptr uint32): EfiStatus {.cdecl.}
    allocatePool*:  proc(poolType: EfiMemoryType, size: uint, buffer: ptr pointer): EfiStatus {.cdecl.}
    freePool*:      proc(buffer: pointer): EfiStatus {.cdecl.}

    createEvent*:  pointer
    setTimer*:     pointer
    waitForEvent*: pointer
    signalEvent*:  pointer
    closeEvent*:   pointer
    checkEvent*:   pointer

    installProtocolInterface*:   pointer
    reinstallProtocolInterface*: pointer
    uninstallProtocolInterface*: pointer
    handleProtocol*: proc(handle: EfiHandle, protocol: ptr EfiGuid, interfacePtr: ptr pointer): EfiStatus {.cdecl.}
    reserved*: pointer
    registerProtocolNotify*: pointer
    locateHandle*: pointer
    locateDevicePath*: pointer
    installConfigurationTable*: pointer

    loadImage*:   pointer
    startImage*:  pointer
    exit*:        pointer
    unloadImage*: pointer
    exitBootServices*: proc(imageHandle: EfiHandle, mapKey: uint): EfiStatus {.cdecl.}

    getNextMonotonicCount*: pointer
    stall*: proc(microseconds: uint): EfiStatus {.cdecl.}
    setWatchdogTimer*: pointer

    connectController*:    pointer
    disconnectController*: pointer

    openProtocol*:  pointer
    closeProtocol*: pointer
    openProtocolInformation*: pointer

    protocolsPerHandle*: pointer
    locateHandleBuffer*: pointer
    locateProtocol*: proc(protocol: ptr EfiGuid, registration: pointer,
                           interfacePtr: ptr pointer): EfiStatus {.cdecl.}
    installMultipleProtocolInterfaces*: pointer
    uninstallMultipleProtocolInterfaces*: pointer

    calculateCrc32*: pointer
    copyMem*: pointer
    setMem*:  pointer
    createEventEx*: pointer

  EfiSystemTable* = object
    hdr*: array[3, uint64]
    firmwareVendor*:  ptr uint16
    firmwareRevision*: uint32
    consoleInHandle*: EfiHandle
    conIn*:           pointer
    consoleOutHandle*: EfiHandle
    conOut*:          ptr EfiTextOutputProtocol
    standardErrorHandle*: EfiHandle
    stdErr*:          ptr EfiTextOutputProtocol
    runtimeServices*: pointer
    bootServices*:    ptr EfiBootServices
    numberOfTableEntries*: uint
    configurationTable*:   pointer

  EfiFileProtocol* = object
    revision*:   uint64
    open*:       proc(this: ptr EfiFileProtocol, newHandle: ptr ptr EfiFileProtocol,
                       fileName: ptr uint16, openMode: uint64, attributes: uint64): EfiStatus {.cdecl.}
    close*:      proc(this: ptr EfiFileProtocol): EfiStatus {.cdecl.}
    delete*:     pointer
    read*:       proc(this: ptr EfiFileProtocol, bufferSize: ptr uint, buffer: pointer): EfiStatus {.cdecl.}
    write*:      pointer
    getPosition*: pointer
    setPosition*: pointer
    getInfo*:    proc(this: ptr EfiFileProtocol, infoType: ptr EfiGuid,
                       bufferSize: ptr uint, buffer: pointer): EfiStatus {.cdecl.}
    setInfo*:    pointer
    flush*:      pointer

  EfiSimpleFileSystemProtocol* = object
    revision*:   uint64
    openVolume*: proc(this: ptr EfiSimpleFileSystemProtocol,
                       root: ptr ptr EfiFileProtocol): EfiStatus {.cdecl.}

const
  EfiSimpleFileSystemProtocolGuid* = EfiGuid(
    data1: 0x0964e5b22'u32, data2: 0x6459'u16, data3: 0x11d2'u16,
    data4: [0x8e'u8, 0x39'u8, 0x00'u8, 0xa0'u8, 0xc9'u8, 0x69'u8, 0x72'u8, 0x3b'u8],
  )
  EfiFileModeRead* = 0x0000000000000001'u64
  EfiBufferTooSmall* = 5'u  # EFI_STATUS: EFI_BUFFER_TOO_SMALL (bit oznaczający błąd + kod 5)
  StatusSuccess* = 0'u

{.pop.}
