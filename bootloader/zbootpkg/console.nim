{.push checks: off, stackTrace: off, lineTrace: off.}

import ./uefi_types

var gSystemTable*: ptr EfiSystemTable

proc setSystemTable*(st: ptr EfiSystemTable) =
  gSystemTable = st

proc efiPrint*(s: string) =
  ## Konwertuje ASCII -> UTF-16 (CHAR16*, wymagane przez ConOut->OutputString)
  ## i wypisuje na konsolę firmware. Bufor 512 znaków wystarcza na
  ## standardowe komunikaty diagnostyczne bootloadera.
  var buf: array[512, uint16]
  var i = 0
  for c in s:
    if i >= buf.len - 2: break
    if c == '\n':
      buf[i] = uint16(13) # CR
      inc i
      buf[i] = uint16(10) # LF
      inc i
    else:
      buf[i] = uint16(ord(c))
      inc i
  buf[i] = 0'u16
  discard gSystemTable.conOut.outputString(gSystemTable.conOut, addr buf[0])

proc efiPrintHex*(label: string, value: uint64) =
  const hexDigits = "0123456789ABCDEF"
  var buf = "0000000000000000"
  var v = value
  for i in countdown(15, 0):
    buf[i] = hexDigits[int(v and 0xF)]
    v = v shr 4
  efiPrint(label & ": 0x" & buf & "\n")

proc panic*(msg: string) {.noreturn.} =
  efiPrint("\n[zboot] PANIKA: ")
  efiPrint(msg)
  efiPrint("\nSystem zatrzymany.\n")
  while true:
    discard # TODO: `hlt` przez inline asm — bezpieczne dopiero po ExitBootServices;
            # przed tym momentem zatrzymanie CPU należy do firmware.

{.pop.}
