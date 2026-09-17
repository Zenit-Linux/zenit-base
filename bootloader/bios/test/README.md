# Testy backendu BIOS bootloadera (`bootloader/bios/`)

Ten katalog zawiera **testowe jądro** (`testkernel.asm`) używane wyłącznie
do automatycznej weryfikacji `bootloader/bios/stage1.asm` +
`bootloader/bios/stage2.asm` w QEMU. **To nie jest jądro Zenit Linux** —
to samodzielny, minimalny program ELF64, który sprawdza, że backend BIOS
poprawnie doprowadza procesor od BIOS-owego MBR aż do 64-bitowego jądra
higher-half z poprawnymi uprawnieniami stron.

## Co dokładnie jest sprawdzane

1. **Dotarcie do long mode** — jeśli stage2 nie dotrze do trybu długiego
   (błąd w PAE/EFER.LME/CR0.PG), `testkernel.asm` po prostu się nie
   uruchomi.
2. **Poprawność `BootInfo`** — jądro wypisuje przez port szeregowy
   `firmwareKind`, `kernelBase`, `kernelEntry` i `e820EntryCount`
   odczytane z wskaźnika w `RDI` (System V AMD64 ABI).
3. **Higher-half** — `testkernel.asm` jest linkowany pod adresem
   wirtualnym `0xFFFFFFFF80100000` (patrz `linker.ld`), więc samo
   dotarcie do jego kodu dowodzi, że stage2 poprawnie przeniosło segmenty
   ELF pod wysoki adres wirtualny przy niskiej fizycznej bazie
   (`0x200000`).
4. **Uprawnienia stron per-segment** — `linker.ld` celowo wymusza **dwa
   oddzielne segmenty PT_LOAD** (`.text` jako R+X, `.rodata`/`.data`/`.bss`
   jako R+W). `testkernel.asm` odczytuje realne wpisy PTE (przez `CR3`)
   dla adresu w `.text` i w `.data` i sprawdza, że stage2 faktycznie
   nadało różne uprawnienia (m.in. bit NX ustawiony tylko dla `.data`).

Wynik jest raportowany przez port szeregowy (`WYNIK = PASS`/`WYNIK = FAIL`)
**oraz** przez urządzenie QEMU `isa-debug-exit` (port `0xF4`) — QEMU kończy
działanie z kodem procesu `(AL << 1) | 1`, czyli `33` dla PASS (`AL=0x10`)
i `35` dla FAIL (`AL=0x11`). Dzięki temu wynik testu można sprawdzić
programowo (patrz `.github/workflows/build-bootloader-bios.yml`), bez
zgadywania na podstawie samego timeoutu.

## Uruchomienie lokalnie

Wymagania: `nasm`, `binutils` (`ld`, `readelf`), `qemu-system-x86_64`,
Python 3.

```bash
# 1. Zbuduj stage1.bin + stage2.bin
nimble buildBootloaderBios

# 2. Zbuduj testowe jądro
nasm -f elf64 -o /tmp/testkernel.o bootloader/bios/test/testkernel.asm
ld -T bootloader/bios/test/linker.ld -o /tmp/testkernel.elf /tmp/testkernel.o

# (opcjonalnie) sprawdź, że linker faktycznie utworzył 2 segmenty PT_LOAD:
readelf -lW /tmp/testkernel.elf

# 3. Złóż surowy obraz dysku (stage1 + stage2 + testkernel.elf)
python3 scripts/make-bios-image.py --kernel /tmp/testkernel.elf --out /tmp/bios-disk.img

# 4. Uruchom w QEMU
qemu-system-x86_64 \
  -machine pc -m 256 \
  -drive format=raw,file=/tmp/bios-disk.img \
  -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
  -serial stdio -display none -no-reboot
echo "kod wyjścia QEMU: $?"   # 33 = PASS
```

Oczekiwany log (kolejność może się nieznacznie różnić w szczegółach
mapy E820 zależnie od konfiguracji `-m`):

```
zboot-bios: stage2 -- real mode
zboot-bios: tryb graficzny VBE ustawiony (liniowy framebuffer)
zboot-bios: obraz jadra wczytany z dysku
zboot-bios: przechodze do trybu chronionego (32-bit)
zboot-bios: tryb dlugi, jadro zaladowane i zmapowane -- skok...
testkernel: wejscie higher-half osiagniete (RDI=BootInfo*)
testkernel: firmwareKind = 0x01
testkernel: kernelBase   = 0x0000000000200000
testkernel: kernelEntry  = 0xFFFFFFFF80100000
testkernel: e820EntryCount = 0x00000007
testkernel: PTE(.text) = 0x0000000000200021
testkernel: PTE(.data) = 0x8000000000201063
testkernel: WYNIK = PASS
```

(Linia `tryb graficzny VBE` zależy od tego, co emuluje/raportuje BIOS —
przy `-vga none` albo firmware bez VBE zamiast niej pojawi się
`VBE niedostepne/brak pasujacego trybu -- bez framebuffera`; obie ścieżki
są prawidłowe i nie wpływają na wynik testu `testkernel`, patrz sekcja
"Wykrywanie trybu graficznego VBE" niżej.)

## Ograniczenia tej ścieżki testowej (i całego backendu BIOS na tym etapie)

- **Brak systemu plików** — `stage2.asm` czyta jądro jako surowe sektory
  pod stałym LBA (patrz stałe `KERNEL_HDR_LBA`/`KERNEL_DATA_LBA` w
  `stage2.asm` i `scripts/make-bios-image.py`), nie z FAT jak backend
  UEFI. `make-bios-image.py` musi więc sam zbudować cały obraz dysku
  zamiast kopiować pojedynczy plik na istniejący wolumin.
- **Limit rozmiaru jądra ~448 KiB** — bufor startowy w pamięci
  konwencjonalnej (`KERNEL_STAGE_MAXSZ` w `stage2.asm`) jest z założenia
  prosty (real mode nie adresuje bezpośrednio pamięci >1 MiB bez dalszych
  sztuczek) — wystarczający dla testowego jądra, docelowe jądro Zenit
  Linux prawdopodobnie będzie wymagało rozszerzenia tego mechanizmu.
- **Stała fizyczna baza jądra** (`KERNEL_PHYS_BASE = 0x200000`) — backend
  UEFI alokuje ją dynamicznie przez `AllocatePages`; BIOS na tym etapie
  nie ma odpowiednika takiego alokatora przed włączeniem stronicowania.

## Wykrywanie trybu graficznego VBE (`detect_vbe` w `stage2.asm`)

Odpowiednik `zbootpkg/graphics` po stronie UEFI: w 16-bit real mode, przed
przejściem do trybu chronionego, `stage2.asm` odpytuje BIOS przez VBE
(VESA BIOS Extensions, `INT 10h/AX=4Fxxh`) o dostępne tryby graficzne,
wybiera ten o największej rozdzielczości z dostępnym liniowym
framebufferem i ustawia go — dokładnie ta sama logika co
`graphics.selectHighestResolutionMode` po stronie UEFI (`QueryMode` dla
każdego trybu, `SetMode` na zwycięzcy), tylko przez inne API firmware.
Best-effort: brak VBE albo brak pasującego trybu zostawia
`BootInfo.fbBase = 0`, dokładnie jak `FramebufferInfo(present: false)`
po stronie UEFI.

**Przetestowane rzeczywiście w QEMU** (nie tylko zasemblowane) w trzech
konfiguracjach:

```bash
qemu-system-x86_64 -machine pc -m 256 -vga std   ...   # WYNIK = PASS, VBE ustawione (3840x2160x16bpp w tej wersji QEMU)
qemu-system-x86_64 -machine pc -m 256            ...   # WYNIK = PASS, VBE ustawione (domyślne urządzenie graficzne)
qemu-system-x86_64 -machine pc -m 256 -vga none  ...   # WYNIK = PASS, VBE niedostępne -- poprawny fallback
```

We wszystkich trzech przypadkach `testkernel` nadal kończy się `WYNIK =
PASS` — `detect_vbe` nie wpływa na resztę ścieżki rozruchu niezależnie od
tego, czy znalazło i ustawiło tryb graficzny.

**Uwaga historyczna**: pierwsza wersja `detect_vbe` miała błąd wykryty
DOPIERO przez to rzeczywiste uruchomienie w QEMU (nie przez samo
zasemblowanie, które nie wykrywa błędów logicznych) — instrukcja
`mul ecx` użyta do wyliczenia `XResolution * YResolution` zapisuje górną
połowę 64-bitowego iloczynu w `EDX`, co przy okazji zerowało `DX` w
większości przypadków (gdy iloczyn mieścił się w 16 bitach, co dotyczy
większości rozdzielczości VBE) — a w `DX` był zapamiętany numer
aktualnie sprawdzanego trybu, potrzebny 20 linijek niżej do zapisania w
`vbe_mode_number`. Efekt: żaden tryb nigdy nie był faktycznie wybierany,
mimo poprawnego przejścia przez wszystkie wcześniejsze filtry —
`detect_vbe` zawsze kończyło się na gałęzi "VBE niedostępne", cicho i
bez żadnego błędu. Naprawione przez `push dx`/`pop dx` wokół `mul ecx`.
Ten rodzaj błędu (rejestr skasowany przez pozornie niepowiązaną
instrukcję kilka linijek dalej) to dokładnie to, czego sama poprawność
składniowa (`nasm` bez błędów) nie wykrywa — stąd waga faktycznego
uruchomienia w QEMU, a nie tylko zasemblowania, dla tej klasy zmian.

## Weryfikacja linii A20 (`check_a20` w `stage2.asm`)

`enable_a20` (BIOS `INT 15h/AX=2401h` + "fast A20 gate" port `0x92`)
istniało już wcześniej, ale bez sprawdzenia, czy FAKTYCZNIE zadziałało —
niektóre BIOS-y potrafią zgłosić sukces, mimo że linia A20 pozostaje
wyłączona. `check_a20` to klasyczny test "zawijania" adresu (OSDev Wiki
"A20 Line"): zapisuje różne bajty pod adresem liniowym `0x000500` i
`0x100500` (`FFFF:0510`) i sprawdza, czy się aliasują (A20 wyłączona =
`0x100500` zawija się modulo 1 MiB i trafia w ten sam bajt fizyczny co
`0x000500`).

To NIE jest kosmetyczna kontrola: jądro Zenit Linux ładuje się pod
`KERNEL_PHYS_BASE=0x200000`, POWYŻEJ granicy 1 MiB — bez działającej A20
kopiowanie segmentów ELF zawinęłoby się i nadpisało pamięć w okolicy
`0x100000` zamiast `0x200000`, co jest cichą korupcją pamięci, a nie od
razu widocznym błędem. `entry16` woła `check_a20` zaraz po `enable_a20`
i przy wykrytym błędzie **zatrzymuje się z jasnym komunikatem** zamiast
kontynuować w stronę takiej korupcji.

**Przetestowane rzeczywiście w QEMU w obu kierunkach**:
- Normalny rozruch (A20 włączona, tak jak domyślnie w QEMU): `check_a20`
  poprawnie zgłasza "włączona", rozruch przechodzi bez zmian, `WYNIK = PASS`.
- Wymuszone zamknięcie bramki A20 tuż przed sprawdzeniem (`in al,0x92 /
  and al,0xFD / out 0x92,al` zamiast `enable_a20`, żeby faktycznie
  odtworzyć stan "wyłączona" na poziomie sprzętu, a nie tylko pominąć
  wywołanie funkcji): `check_a20` poprawnie wykrywa brak A20, wypisuje
  `zboot-bios: BLAD -- linia A20 nie dziala mimo prob wlaczenia -- zatrzymuje sie`
  i zatrzymuje się (pętla `halt16`, zamiast kontynuować w stronę
  niezdefiniowanego zachowania).
