{.push checks: off, stackTrace: off, lineTrace: off.}

import ./uefi_types

var gSystemTable*: ptr EfiSystemTable
var gBootServicesExited*: bool = false
  ## Ustawiane przez zboot.nim TUŻ PO udanym ExitBootServices(). Zanim to
  ## nastąpi, zatrzymanie CPU (np. przez `hlt`) należy do firmware — nie
  ## wiemy, czy jakiś inny wątek/AP nie oczekuje, że BSP wciąż aktywnie
  ## odpowiada, więc `panic()` przed tym momentem musi zostać przy
  ## czystym busy-spinie. PO ExitBootServices żadne takie założenie już
  ## nie obowiązuje (firmware oddał nam całą maszynę), więc można bez
  ## obaw użyć `hlt` w pętli, co oszczędza energię/ciepło zamiast
  ## wypalać rdzeń w nieskończonej pustej pętli.

proc markBootServicesExited*() =
  gBootServicesExited = true

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
  ## Jak `efiPrint`, ale dopisuje `value` w hex. Celowo NIE używa
  ## mutowania ani konkatenacji Nim `string` (`buf[i] = ...`, `a & b`) --
  ## rzeczywisty test w QEMU+OVMF pokazał, że mutacja indeksowana `string`
  ## powoduje twardy crash (triple fault) w tym freestanding środowisku
  ## UEFI, jeszcze PRZED dotarciem do własnego alokatora
  ## (zbootpkg/allocator) — coś w wewnętrznej maszynerii ARC dla
  ## mutowalnych/konkatenowanych stringów nie działa poprawnie pod
  ## `--os:any -d:useMalloc -nostdlib`. Zamiast tego pracujemy WYŁĄCZNIE
  ## na tablicach o stałym rozmiarze (ten sam, sprawdzony wzorzec co w
  ## `efiPrint`), z pojedynczym wywołaniem `OutputString` na końcu.
  const hexDigits = "0123456789ABCDEF"
  var buf: array[512, uint16]
  var i = 0

  for c in label:
    if i >= buf.len - 20: break
    buf[i] = uint16(ord(c))
    inc i

  buf[i] = uint16(ord(':')); inc i
  buf[i] = uint16(ord(' ')); inc i
  buf[i] = uint16(ord('0')); inc i
  buf[i] = uint16(ord('x')); inc i

  var v = value
  var digits: array[16, char]
  for k in countdown(15, 0):
    digits[k] = hexDigits[int(v and 0xF)]
    v = v shr 4
  for c in digits:
    buf[i] = uint16(ord(c))
    inc i

  buf[i] = uint16(13); inc i # CR
  buf[i] = uint16(10); inc i # LF
  buf[i] = 0'u16

  discard gSystemTable.conOut.outputString(gSystemTable.conOut, addr buf[0])

proc efiPrintUInt*(value: uint64) =
  ## Wypisuje `value` jako liczbę dziesiętną, BEZ znaku nowej linii na
  ## końcu (żeby dało się łączyć z `efiPrint()` przy budowaniu linii
  ## kawałek po kawałku, zamiast konkatenacji `&`/interpolacji `$` na
  ## Nim `string` — patrz obszerna notatka przy `efiPrintHex` o tym,
  ## czemu tego unikamy w tym środowisku).
  if value == 0:
    efiPrint("0")
    return

  var digits: array[20, char] # uint64 mieści się maksymalnie w 20 cyfrach dziesiętnych
  var n = 0
  var v = value
  while v > 0:
    digits[n] = char(ord('0') + int(v mod 10'u64))
    v = v div 10'u64
    inc n

  var buf: array[32, uint16]
  var i = 0
  for k in countdown(n - 1, 0):
    buf[i] = uint16(ord(digits[k]))
    inc i
  buf[i] = 0'u16
  discard gSystemTable.conOut.outputString(gSystemTable.conOut, addr buf[0])

proc panic*(msg: string) {.noreturn.} =
  efiPrint("\n[zboot] PANIKA: ")
  efiPrint(msg)
  efiPrint("\nSystem zatrzymany.\n")
  while true:
    if gBootServicesExited:
      # Bezpieczne dopiero PO ExitBootServices -- patrz komentarz przy
      # `gBootServicesExited` wyżej. `hlt` zatrzymuje CPU do najbliższego
      # przerwania (np. timera), po czym pętla po prostu wykonuje `hlt`
      # ponownie -- standardowy wzorzec pętli bezczynności jądra.
      asm """
        hlt
      """
    else:
      discard # przed ExitBootServices zatrzymanie CPU należy do firmware

{.pop.}
