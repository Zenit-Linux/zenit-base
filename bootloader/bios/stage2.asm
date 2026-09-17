BITS 16
ORG 0x8000

; ----------------------------------------------------------------------------
; Mapa pamieci uzywana przez ten loader (wszystko ponizej granicy 1 MiB,
; zeby pozostac osiagalne z trybu rzeczywistego przez segment:offset):
;
;   0x00007E00 - 0x00007FFF   bufor pomocniczy (naglowek rozmiaru jadra)
;   0x00008000 - 0x0000BFFF   stage2 (ten plik, budzet 16 KiB / 32 sektory)
;   0x0000C000 - 0x0000C7FF   GDT + zmienne stage2
;   0x0000C800 - 0x0000CFFF   bufor mapy pamieci E820 (64 wpisy * 24 B)
;   0x0000D800 - 0x0000D9FF   bufor VBE Controller Info (512 B, INT 10h/4F00h)
;   0x0000DA00 - 0x0000DAFF   bufor VBE Mode Info (256 B, INT 10h/4F01h)
;   0x0000E000 - 0x0000FFF0   stos dla fazy 64-bit (8 KiB)
;   0x00010000 - 0x00011FFF   struktura BootInfo przekazywana do jadra
;   0x00020000 - 0x0008FFFF   bufor startowy surowego obrazu ELF64 jadra (448 KiB)
;   0x00090000 - 0x0009F7FF   pula tablic stron (przydzial "bump", ~62 KiB)
;
; Powyzej 0x0009F800 celowo nie wchodzimy -- rezerwa na ewentualny EBDA
; (Extended BIOS Data Area), ktorego dokladny poczatek rozni sie miedzy
; platformami, oraz na obszar VGA/BIOS ROM zaczynajacy sie od 0x000A0000.
; ----------------------------------------------------------------------------
KERNEL_HDR_LBA        equ 33            ; sektor z 8-bajtowym rozmiarem jadra (LE)
KERNEL_DATA_LBA        equ 34           ; pierwszy sektor surowych bajtow ELF64
KERNEL_HDR_BUF          equ 0x7E00      ; bufor na sektor z naglowkiem rozmiaru

KERNEL_STAGE_SEG         equ 0x2000     ; segment bufora startowego (real mode)
KERNEL_STAGE_LINEAR       equ 0x00020000
KERNEL_STAGE_MAXSZ         equ 0x00070000 ; 448 KiB -- limit tej prostej sciezki

E820_BUFFER                equ 0x0000C800
E820_MAX_ENTRIES             equ 64
E820_ENTRY_SIZE                equ 24

VBE_INFO_BUF                     equ 0x0000D800   ; 512 B (INT 10h/AX=4F00h)
VBE_MODE_BUF                      equ 0x0000DA00   ; 256 B (INT 10h/AX=4F01h)

BOOTINFO_ADDR                   equ 0x00010000

PAGETABLE_POOL_START             equ 0x00090000
PAGETABLE_POOL_END                equ 0x0009F800

STACK64_TOP                        equ 0x0000FFF0

KERNEL_PHYS_BASE                    equ 0x00200000  ; 2 MiB, stala (brak alokatora)
IDENTITY_MAP_GIB                     equ 4

; Selektory GDT (patrz gdt_start nizej).
SEL_CODE32                            equ 0x08
SEL_DATA32                             equ 0x10
SEL_CODE64                              equ 0x18
SEL_DATA64                               equ 0x20

; ----------------------------------------------------------------------------
entry16:
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov [boot_drive], dl

    mov si, msg_stage2
    call print_string

    call serial_init
    mov si, msg_stage2
    call serial_print

    call detect_memory
    call enable_a20

    call check_a20
    test ax, ax
    jnz .a20_ok
    ; A20 wyglada na wylaczona mimo enable_a20 -- patrz obszerny komentarz
    ; przy check_a20 o tym, dlaczego to NIE jest cos, co mozna bezpiecznie
    ; zignorowac (jadro laduje sie powyzej granicy 1 MiB). Zatrzymujemy sie
    ; tu z jasnym komunikatem zamiast kontynuowac w strone cichej korupcji.
    mov si, msg_a20_fail
    call print_string
    call serial_print
    jmp halt16
.a20_ok:
    call detect_vbe
    call load_kernel_image

    mov si, msg_pm
    call print_string
    call serial_print

    cli
    lgdt [gdt_descriptor]

    mov eax, cr0
    or eax, 1
    mov cr0, eax

    ; UWAGA: `dword` wymusza 32-bitowe kodowanie offsetu tego dalekiego skoku
    ; (0xEA + ptr16:32) mimo ze jestesmy jeszcze w sekcji [BITS 16] -- bez
    ; tego NASM domyslnie zakodowalby ptr16:16, co jest niepoprawna forma
    ; przy wchodzeniu do 32-bitowego segmentu kodu (standardowa pulapka,
    ; patrz OSDev Wiki "Protected Mode").
    jmp dword SEL_CODE32:entry32

; ----------------------------------------------------------------------------
; SI -> lancuch ASCIIZ, wypisywany przez BIOS teletype (INT 10h, AH=0Eh).
print_string:
    push ax
    push bx
    push si
.next:
    lodsb
    or al, al
    jz .done
    mov ah, 0x0E
    xor bx, bx
    int 0x10
    jmp .next
.done:
    pop si
    pop bx
    pop ax
    ret

; ----------------------------------------------------------------------------
; Prosty port szeregowy COM1 (0x3F8), 38400 8N1 -- wylacznie diagnostyka,
; widoczna w QEMU przez `-serial stdio`/`-serial file:...` oraz na realnym
; sprzecie przez kabel null-modem. Odpowiednik roli zbootpkg/console na
; sciezce UEFI (tam uzywajacej ConOut zamiast UART-u).
serial_init:
    push ax
    push dx
    mov dx, 0x3F9        ; IER -- wylacz przerwania
    xor al, al
    out dx, al
    mov dx, 0x3FB        ; LCR -- ustaw DLAB=1, zeby zaprogramowac dzielnik
    mov al, 0x80
    out dx, al
    mov dx, 0x3F8         ; dzielnik (divisor latch low) -- 115200/3 = 38400 bps
    mov al, 3
    out dx, al
    mov dx, 0x3F9
    xor al, al
    out dx, al
    mov dx, 0x3FB          ; LCR -- 8 bitow, brak parzystosci, 1 bit stopu, DLAB=0
    mov al, 0x03
    out dx, al
    mov dx, 0x3FA            ; FCR -- wlacz i wyczysc FIFO
    mov al, 0xC7
    out dx, al
    mov dx, 0x3FC              ; MCR -- DTR/RTS/OUT2
    mov al, 0x0B
    out dx, al
    pop dx
    pop ax
    ret

; SI -> lancuch ASCIIZ
serial_print:
    push ax
    push dx
    push si
.next:
    lodsb
    or al, al
    jz .done
    call serial_putc16
    jmp .next
.done:
    pop si
    pop dx
    pop ax
    ret

; AL = znak do wyslania (tryb 16-bit)
serial_putc16:
    push dx
    push ax
    mov dx, 0x3FD
.wait:
    in al, dx
    test al, 0x20         ; THR empty?
    jz .wait
    pop ax
    mov dx, 0x3F8
    out dx, al
    pop dx
    ret

; ----------------------------------------------------------------------------
; Mapa pamieci przez INT 15h/EAX=0xE820 -- klasyczna petla opisana w
; specyfikacji ACPI (i powszechnie na OSDev wiki). Kazdy wpis dopelniany do
; stalego rozmiaru E820_ENTRY_SIZE (24 B), nawet jesli BIOS zwrocil tylko
; 20 B (bez rozszerzonego pola atrybutow ACPI 3.0) -- upraszcza to parsowanie
; po stronie jadra (stala szerokosc kroku, zamiast zmiennej per wpis).
detect_memory:
    push eax
    push ebx
    push ecx
    push edx
    push edi

    xor ebx, ebx
    mov edi, E820_BUFFER
    xor bp, bp
.loop:
    mov eax, 0xE820
    mov ecx, E820_ENTRY_SIZE
    mov edx, 0x534D4150      ; 'SMAP'
    int 0x15
    jc .done                  ; CF ustawiony -> koniec listy (lub blad od razu)
    cmp eax, 0x534D4150
    jne .done

    cmp ecx, 20
    jne .full_entry
    mov dword [edi + 20], 0   ; brak pola extended attributes -> dopisz zera
.full_entry:
    inc bp
    add edi, E820_ENTRY_SIZE
    cmp bp, E820_MAX_ENTRIES
    jae .done
    test ebx, ebx
    jnz .loop
.done:
    mov [e820_count], bp

    pop edi
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; ----------------------------------------------------------------------------
; Wlaczenie linii A20 -- najpierw przez BIOS (INT 15h/AX=2401h, najbardziej
; przenosne, jesli wspierane), dodatkowo (bezpiecznie) przez "fast A20 gate"
; (port 0x92, bit 1) jako wzmocnienie na platformach, gdzie funkcja BIOS
; nic nie robi lub falszywie zglasza sukces.
enable_a20:
    push ax
    mov ax, 0x2401
    int 0x15

    in al, 0x92
    or al, 2
    and al, 0xFE           ; nie dotykaj bitu 0 (fast reset)
    out 0x92, al
    pop ax
    ret

; ----------------------------------------------------------------------------
; Weryfikuje, czy linia A20 FAKTYCZNIE dziala (klasyczny test "zawijania" z
; OSDev Wiki "A20 Line") -- zamiast slepo ufac kodom powrotu enable_a20,
; ktore niektore BIOS-y potrafia falszywie zglosic jako sukces.
;
; Metoda: zapisuje RUZNE bajty pod adresem liniowym 0x000500 (ES=0000,
; DI=0500) i pod adresem 0x100500 (DS=FFFF, SI=0510 -- FFFF:0510 daje
; liniowo 0xFFFF0+0x510=0x100500). Jesli A20 jest WYLACZONA, dostep do
; 0x100500 zawija sie modulo 1 MiB i FAKTYCZNIE trafia w 0x000500 -- czyli
; obie lokacje ALIASUJA sie na ten sam bajt fizyczny. Jesli A20 dziala, to
; dwa NIEZALEZNE bajty.
;
; Zwraca: AX=1 jesli A20 wlaczona (brak aliasingu), AX=0 jesli wylaczona.
; Oryginalna zawartosc obu bajtow jest przywracana przed powrotem.
;
; To dlaczego ten test jest wazny wlasnie TU: jadro Zenit Linux laduje sie
; pod KERNEL_PHYS_BASE=0x200000 (POWYZEJ granicy 1 MiB) -- bez dzialajacej
; A20 kopiowanie segmentow ELF zawineloby sie i nadpisalo pamiec w okolicy
; 0x100000 zamiast 0x200000, co jest cicha, trudna do zdiagnozowania
; korupcja pamieci, a nie od razu widocznym bledem.
check_a20:
    push es
    push ds
    push di
    push si
    push bx
    push cx

    xor ax, ax
    mov es, ax
    mov di, 0x0500

    mov ax, 0xFFFF
    mov ds, ax
    mov si, 0x0510

    mov bl, [es:di]           ; bl = oryginalny bajt pod 0x000500
    mov cl, [ds:si]           ; cl = oryginalny bajt pod (rzekomo) 0x100500

    mov byte [es:di], 0x00
    mov byte [ds:si], 0xFF

    ; Jesli A20 wylaczona, powyzszy zapis 0xFF pod FFFF:0510 nadpisal
    ; TEN SAM fizyczny bajt co ES:DI (alias) -- odczyt ponizej da wtedy
    ; 0xFF zamiast 0x00.
    mov al, [es:di]

    mov byte [es:di], bl      ; przywroc oryginalna zawartosc 0x000500
    mov byte [ds:si], cl      ; przywroc oryginalna zawartosc 0x100500 (albo aliasu)

    cmp al, 0xFF
    je .disabled
    mov ax, 1
    jmp .done
.disabled:
    xor ax, ax
.done:
    pop cx
    pop bx
    pop si
    pop di
    pop ds
    pop es
    ret

; ----------------------------------------------------------------------------
; Wykrywanie i ustawianie graficznego trybu VBE (VESA BIOS Extensions) --
; odpowiednik zbootpkg/graphics.getFramebufferInfo + selectHighestResolutionMode
; po stronie UEFI. MUSI wykonac sie TUTAJ, w 16-bit real mode -- INT 10h/AX=4Fxx
; (VBE) to funkcje BIOS-u, niedostepne po przejsciu do trybu chronionego.
;
; Algorytm (identyczny w duchu do UEFI GOP -- "sprawdz wszystkie tryby, wybierz
; najwiekszy"):
;   1) INT 10h/AX=4F00h (Get Controller Info) z sygnatura "VBE2" wpisana
;      z gory do bufora -- prosi kontroler o rozszerzone info VBE 2.0+
;      (w tym PhysBasePtr w Mode Info pozniej). Zwraca m.in. daleki
;      wskaznik (segment:offset, offset 0x0E/0x10) do listy numerow
;      obslugiwanych trybow, zakonczonej wartoscia 0xFFFF.
;   2) Dla kazdego numeru trybu z tej listy: INT 10h/AX=4F01h (Get Mode
;      Info) -> sprawdz ModeAttributes (bit0=obslugiwany, bit4=graficzny,
;      bit7=dostepny liniowy framebuffer), BitsPerPixel >= 15 (pomijamy
;      tryby palety 4/8bpp -- nieuzyteczne jako prosty RGB framebuffer)
;      i MemoryModel == 6 (Direct Color -- gwarantuje sensowne
;      RedFieldPosition/BlueFieldPosition do rozpoznania kolejnosci
;      bajtow RGB/BGR). Zapamietaj tryb o najwiekszej liczbie pikseli
;      (XResolution*YResolution).
;   3) Jesli znaleziono jakikolwiek pasujacy tryb: INT 10h/AX=4F02h (Set
;      Mode) z bitem 0x4000 ustawionym w BX (uzyj liniowego framebuffera
;      zamiast bankowanego -- funkcja dostepna od VBE 2.0).
;
; Best-effort: brak VBE, brak pasujacego trybu, albo nieudany Set Mode ->
; vbe_mode_number zostaje 0, a BootInfo.fbBase (wypelniane pozniej w
; entry64) zostaje zerowe -- jadro dostaje sygnal "brak framebuffera",
; dokladnie jak FramebufferInfo(present: false) po stronie UEFI.
;
; UWAGA nt. bezpieczenstwa segmentow: DS pozostaje 0 (nasz wlasny segment
; danych) przez CALA te procedure -- ES jest jedynym rejestrem segmentowym
; przelaczanym tymczasowo (na segment listy trybow zwrocony przez BIOS),
; i jest jawnie przywracane na 0 PRZED kazdym kolejnym wywolaniem INT 10h,
; bo nasze wlasne bufory (VBE_INFO_BUF/VBE_MODE_BUF) zyja w segmencie 0.
detect_vbe:
    pusha
    push es
    push ds

    xor ax, ax
    mov ds, ax
    mov es, ax

    ; --- Get Controller Info (sygnatura VBE2 -> rozszerzone pola 2.0+) ---
    mov dword [VBE_INFO_BUF], 'VBE2'
    mov di, VBE_INFO_BUF
    mov ax, 0x4F00
    int 0x10
    cmp ax, 0x004F
    jne .no_vbe

    ; --- daleki wskaznik na liste numerow trybow (offset 0x0E/0x10) ---
    mov ax, [VBE_INFO_BUF + 0x10]   ; segment listy trybow
    mov [vbe_list_seg], ax
    mov ax, [VBE_INFO_BUF + 0x0E]   ; offset listy trybow
    mov [vbe_list_off], ax

    mov dword [vbe_best_pixels], 0
    mov word [vbe_mode_number], 0

.mode_loop:
    ; --- odczytaj kolejny numer trybu (segment obcy przez ES, offset z
    ;     naszej wlasnej zmiennej w DS) ---
    mov ax, [vbe_list_seg]
    mov es, ax
    mov si, [vbe_list_off]
    mov dx, [es:si]                  ; biezacy numer trybu (word)
    add word [vbe_list_off], 2

    cmp dx, 0xFFFF
    je .mode_loop_done               ; 0xFFFF konczy liste

    ; --- Get Mode Info dla trybu DX -- ES musi wrocic na 0 PRZED tym
    ;     wywolaniem: lista trybow zyje w segmencie BIOS-u, ale nasz
    ;     bufor VBE_MODE_BUF jest w segmencie 0 ---
    push dx
    xor ax, ax
    mov es, ax
    mov di, VBE_MODE_BUF
    mov cx, dx
    mov ax, 0x4F01
    int 0x10
    pop dx
    cmp ax, 0x004F
    jne .mode_loop                   ; ten tryb nieobslugiwany -- sprobuj kolejny

    ; --- ModeAttributes: bit0 (obslugiwany), bit4 (graficzny), bit7 (LFB) ---
    mov ax, [VBE_MODE_BUF + 0x00]
    test ax, 0x0001
    jz .mode_loop
    test ax, 0x0010
    jz .mode_loop
    test ax, 0x0080
    jz .mode_loop

    ; --- BitsPerPixel >= 15 (pomijamy tryby palety, np. 4/8bpp) ---
    mov al, [VBE_MODE_BUF + 0x19]
    cmp al, 15
    jb .mode_loop

    ; --- MemoryModel == 6 (Direct Color) -- gwarantuje sensowne pola
    ;     RedFieldPosition/BlueFieldPosition nizej; przy bpp>=15 to
    ;     prawie zawsze prawda na realnym i emulowanym sprzecie, ale
    ;     wolimy pominac tryb niz zgadywac uklad bajtow ---
    mov al, [VBE_MODE_BUF + 0x1B]
    cmp al, 6
    jne .mode_loop

    ; --- policz piksele = XResolution * YResolution (32-bit, bezpieczne:
    ;     kazdy czynnik <= 65535, wiec iloczyn nie przekracza 32 bitow) ---
    ; UWAGA (blad znaleziony i naprawiony przez rzeczywisty test w QEMU):
    ;     `mul ecx` zapisuje GORNA polowe 64-bitowego iloczynu w EDX,
    ;     co niszczy DX -- A WLASNIE W DX SIEDZI NUMER TRYBU zapamietany
    ;     wczesniej w tej iteracji petli! Dla rozdzielczosci, ktorych
    ;     iloczyn miesci sie w 16 bitach (EDX=0 po `mul`, bo brak
    ;     przepelnienia -- co dotyczy WIEKSZOSCI trybow VBE), DX wychodzil
    ;     wtedy jako 0, a `mov [vbe_mode_number], dx` nizej zapisywalo
    ;     ZERO zamiast prawdziwego numeru trybu -- w efekcie ZADEN tryb
    ;     nigdy nie zostawal faktycznie wybrany, mimo poprawnego
    ;     przejscia przez wszystkie wczesniejsze filtry. Stad `push dx`/
    ;     `pop dx` wokol `mul` ponizej.
    push dx
    movzx eax, word [VBE_MODE_BUF + 0x12]   ; XResolution
    movzx ecx, word [VBE_MODE_BUF + 0x14]   ; YResolution
    mul ecx
    pop dx
    cmp eax, [vbe_best_pixels]
    jbe .mode_loop                           ; nie lepszy niz dotychczasowy najlepszy

    mov [vbe_best_pixels], eax
    mov [vbe_mode_number], dx
    movzx eax, word [VBE_MODE_BUF + 0x12]
    mov [vbe_best_width], ax
    movzx eax, word [VBE_MODE_BUF + 0x14]
    mov [vbe_best_height], ax
    movzx eax, word [VBE_MODE_BUF + 0x10]   ; BytesPerScanLine
    mov [vbe_best_pitch], ax
    mov al, [VBE_MODE_BUF + 0x19]
    mov [vbe_best_bpp], al
    mov eax, [VBE_MODE_BUF + 0x28]           ; PhysBasePtr (VBE 2.0+)
    mov [vbe_best_physbase], eax

    ; --- kolejnosc bajtow RGB/BGR: porownaj pozycje pola Red i Blue
    ;     (offsety 0x20/0x24) -- jesli Red lezy WYZEJ (wieksza pozycja
    ;     bitowa) niz Blue, to w pamieci (little-endian) najpierw idzie
    ;     Blue -> ukladbajtow "BGR", analogicznie do UEFI
    ;     PixelBlueGreenRedReserved8BitPerColor (pixelFormat=1) ---
    mov al, [VBE_MODE_BUF + 0x20]            ; RedFieldPosition
    mov ah, [VBE_MODE_BUF + 0x24]            ; BlueFieldPosition
    cmp al, ah
    jbe .store_rgb
    mov byte [vbe_best_bgr], 1
    jmp .mode_loop
.store_rgb:
    mov byte [vbe_best_bgr], 0
    jmp .mode_loop

.mode_loop_done:
    xor ax, ax
    mov es, ax                       ; ES z powrotem na 0 -- porzadek po petli

    cmp word [vbe_mode_number], 0
    je .no_vbe

    ; --- Set Mode: numer trybu | 0x4000 (uzyj liniowego framebuffera) ---
    mov bx, [vbe_mode_number]
    or bx, 0x4000
    mov ax, 0x4F02
    int 0x10
    cmp ax, 0x004F
    jne .set_failed

    mov si, msg_vbe_ok
    call print_string
    call serial_print
    jmp .done

.set_failed:
    ; Set Mode zawiodlo mimo ze Get Mode Info zglosilo sukces (zdarza sie
    ; na niektorych kontrolerach) -- zerujemy wynik, jadro dostanie sygnal
    ; "brak framebuffera" zamiast bledny/nieaktywny adres.
    mov word [vbe_mode_number], 0
    mov dword [vbe_best_physbase], 0
.no_vbe:
    mov si, msg_vbe_none
    call print_string
    call serial_print
.done:
    pop ds
    pop es
    popa
    ret

; ----------------------------------------------------------------------------
; Wczytuje surowy obraz ELF64 jadra z dysku:
;   1) sektor naglowkowy (KERNEL_HDR_LBA) zawiera rozmiar jadra w bajtach
;      jako u64 LE (patrz scripts/make-bios-image.py),
;   2) wlasciwe bajty ELF zaczynaja sie od KERNEL_DATA_LBA,
;   3) odczyt w kawalkach po 64 sektory (32 KiB) naraz, zeby nigdy nie
;      przekroczyc granicy segmentu 64 KiB w buforze docelowym.
load_kernel_image:
    push ax
    push bx
    push cx
    push dx
    push si

    ; --- sektor z naglowkiem rozmiaru ---
    mov word [hdr_dap_count], 1
    mov word [hdr_dap_offset], KERNEL_HDR_BUF
    mov word [hdr_dap_segment], 0
    mov dword [hdr_dap_lba_lo], KERNEL_HDR_LBA
    mov dword [hdr_dap_lba_hi], 0

    mov si, hdr_dap
    mov ah, 0x42
    mov dl, [boot_drive]
    int 0x13
    mov [last_ah_status], ah
    jc .disk_err

    mov eax, [KERNEL_HDR_BUF]
    mov [kernel_size_lo], eax
    mov eax, [KERNEL_HDR_BUF + 4]
    or eax, eax
    jz .size_ok
    jmp .too_big              ; rozmiar >= 4 GiB -- poza zakresem tej sciezki
.size_ok:
    mov eax, [kernel_size_lo]
    or eax, eax
    jnz .have_size
    jmp .bad_size
.have_size:
    cmp eax, KERNEL_STAGE_MAXSZ
    ja .too_big

    ; liczba sektorow = ceil(rozmiar / 512)
    add eax, 511
    shr eax, 9
    mov [kernel_sectors_total], eax

    mov dword [cur_lba_lo], KERNEL_DATA_LBA
    mov dword [cur_lba_hi], 0
    mov word [cur_seg], KERNEL_STAGE_SEG
    mov eax, [kernel_sectors_total]
    mov [remaining], eax

.chunk_loop:
    mov eax, [remaining]
    or eax, eax
    jz .done

    cmp eax, 64
    jbe .chunk_size_ok
    mov eax, 64
.chunk_size_ok:
    mov [chunk], eax

    mov ax, [chunk]
    mov word [rd_dap_count], ax
    mov word [rd_dap_offset], 0
    mov ax, [cur_seg]
    mov word [rd_dap_segment], ax
    mov eax, [cur_lba_lo]
    mov [rd_dap_lba_lo], eax
    mov eax, [cur_lba_hi]
    mov [rd_dap_lba_hi], eax

    mov si, rd_dap
    mov ah, 0x42
    mov dl, [boot_drive]
    int 0x13
    mov [last_ah_status], ah
    jc .disk_err

    ; cur_lba += chunk ; cur_seg += chunk*32 (chunk sektorow * 512 B / 16 B-na-paragraf)
    mov eax, [chunk]
    add [cur_lba_lo], eax
    adc dword [cur_lba_hi], 0

    mov eax, [chunk]
    shl eax, 5              ; * 32
    add [cur_seg], ax

    mov eax, [chunk]
    sub [remaining], eax

    jmp .chunk_loop

.done:
    mov si, msg_kernel_ok
    call print_string
    call serial_print
    jmp .ret

.disk_err:
    mov si, msg_disk_err
    call print_string
    call serial_print
    mov al, [last_ah_status]
    call debug_print_hex8_serial
    jmp halt16

.too_big:
    mov si, msg_too_big
    call print_string
    call serial_print
    jmp halt16

.bad_size:
    mov si, msg_bad_size
    call print_string
    call serial_print
    jmp halt16

.ret:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ----------------------------------------------------------------------------
; AL = bajt -> wypisuje 2 cyfry szesnastkowe + CRLF na port szeregowy.
; Uzywane do zdiagnozowania kodu bledu BIOS (AH) po nieudanym INT13h --
; przydatne np. gdy nosnik faktycznie nie odpowiada lub emulacja dysku ma
; ograniczenia (np. maksymalna liczba sektorow na odczyt).
debug_print_hex8_serial:
    push ax
    push bx
    push cx
    mov bl, al
    mov cx, 2
.next_nibble:
    mov al, bl
    shr al, 4
    and al, 0xF
    cmp al, 10
    jae .letter
    add al, '0'
    jmp .emit
.letter:
    add al, 'A' - 10
.emit:
    call serial_putc16
    shl bl, 4
    loop .next_nibble
    mov al, 13
    call serial_putc16
    mov al, 10
    call serial_putc16
    pop cx
    pop bx
    pop ax
    ret

; ----------------------------------------------------------------------------
halt16:
    cli
.hang:
    hlt
    jmp .hang

; ----------------------------------------------------------------------------
boot_drive:            db 0
last_ah_status:        db 0
e820_count:             dw 0
kernel_size_lo:          dd 0
kernel_sectors_total:     dd 0
cur_lba_lo:                dd 0
cur_lba_hi:                 dd 0
cur_seg:                     dw 0
remaining:                    dd 0
chunk:                         dd 0

; --- zmienne VBE (patrz detect_vbe) ---
vbe_list_seg:      dw 0
vbe_list_off:       dw 0
vbe_best_pixels:     dd 0
vbe_mode_number:      dw 0   ; 0 = brak trybu graficznego (fallback bezpieczny)
vbe_best_width:        dw 0
vbe_best_height:        dw 0
vbe_best_pitch:          dw 0  ; BytesPerScanLine
vbe_best_bpp:             db 0
vbe_best_bgr:              db 0
vbe_best_physbase:          dd 0

align 4
hdr_dap:
    db 0x10
    db 0
hdr_dap_count:   dw 0
hdr_dap_offset:   dw 0
hdr_dap_segment:   dw 0
hdr_dap_lba_lo:     dd 0
hdr_dap_lba_hi:      dd 0

align 4
rd_dap:
    db 0x10
    db 0
rd_dap_count:   dw 0
rd_dap_offset:   dw 0
rd_dap_segment:   dw 0
rd_dap_lba_lo:     dd 0
rd_dap_lba_hi:      dd 0

msg_stage2:    db "zboot-bios: stage2 -- real mode", 13, 10, 0
msg_pm:        db "zboot-bios: przechodze do trybu chronionego (32-bit)", 13, 10, 0
msg_kernel_ok: db "zboot-bios: obraz jadra wczytany z dysku", 13, 10, 0
msg_disk_err:  db "zboot-bios: BLAD odczytu dysku (obraz jadra)", 13, 10, 0
msg_too_big:   db "zboot-bios: BLAD -- obraz jadra przekracza limit 448 KiB tej prostej sciezki ladowania", 13, 10, 0
msg_bad_size:  db "zboot-bios: BLAD -- naglowek rozmiaru jadra jest zerowy/uszkodzony", 13, 10, 0
msg_a20_fail:  db "zboot-bios: BLAD -- linia A20 nie dziala mimo prob wlaczenia -- zatrzymuje sie", 13, 10, 0
msg_vbe_ok:    db "zboot-bios: tryb graficzny VBE ustawiony (liniowy framebuffer)", 13, 10, 0
msg_vbe_none:  db "zboot-bios: VBE niedostepne/brak pasujacego trybu -- bez framebuffera", 13, 10, 0

; ----------------------------------------------------------------------------
; GDT -- deskryptory plaskie (base=0, limit=4 GiB) dla code32/data32/code64/
; data64. Wartosci sa standardowymi, powszechnie uzywanymi stalymi (patrz
; np. OSDev Wiki "Global Descriptor Table" / "Setting Up Long Mode") --
; kodowanie: base_low16 | limit_low16 | access8 | (flags4:limit_hi4) | base_hi8.
align 8
gdt_start:
    dq 0x0000000000000000            ; 0x00 null
    dq 0x00CF9A000000FFFF            ; 0x08 code32: G=1,D=1, base=0, limit=4G, RX
    dq 0x00CF92000000FFFF            ; 0x10 data32: G=1,D=1, base=0, limit=4G, RW
    dq 0x00AF9A000000FFFF            ; 0x18 code64: G=1,L=1, base=0, RX
    dq 0x00CF92000000FFFF            ; 0x20 data64: plaski, uzywany jako SS/DS w long mode
gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd gdt_start

; ============================================================================
; 32-bit protected mode -- wylacznie: identity mapping niskiej pamieci,
; wlaczenie PAE/long mode/NXE, wlaczenie stronicowania, skok do 64-bit.
; Cala "ciekawa" praca (parsowanie ELF, kopiowanie segmentow, mapowanie
; per-segment) jest CELOWO odlozona do fazy 64-bit (entry64 nizej), zeby
; korzystac z naturalnej arytmetyki 64-bitowej zamiast rozbijac kazda
; operacje na pary rejestrow 32-bitowych (istotne dla jader higher-half,
; gdzie adresy wirtualne typu 0xFFFFFFFF80000000 nie miesza sie w 32 bitach).
; ============================================================================
BITS 32
entry32:
    mov ax, SEL_DATA32
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x0001F000       ; maly stos 32-bit, ponizej bufora BootInfo

    ; --- zbuduj tablice stron pokrywajace WYLACZNIE identity mapping ---
    call pm32_build_identity_map

    ; --- PAE ---
    mov eax, cr4
    or eax, 1 << 5             ; CR4.PAE
    mov cr4, eax

    mov eax, [pml4_phys]
    mov cr3, eax

    ; --- EFER.LME + EFER.NXE ---
    mov ecx, 0xC0000080
    rdmsr
    or eax, (1 << 8) | (1 << 11)
    wrmsr

    ; --- wlacz stronicowanie (od tego momentu CPU jest w IA-32e, ale nadal
    ; wykonuje kod 32-bit z trybu zgodnosci, dopoki nie zrobimy far jump
    ; do 64-bitowego segmentu kodu ponizej) ---
    mov eax, cr0
    or eax, 1 << 31
    mov cr0, eax

    jmp SEL_CODE64:entry64

; ----------------------------------------------------------------------------
; Prosty przydzial "bump" stron 4 KiB z puli PAGETABLE_POOL_START..
; PAGETABLE_POOL_END, uzywany zarowno w fazie 32-bit (identity map), jak i
; 64-bit (mapowanie segmentow jadra) -- patrz next_free_page ponizej.
; Zwraca adres w EAX, zeruje przydzielona strone.
pm32_alloc_page:
    mov eax, [next_free_page]
    add dword [next_free_page], 0x1000
    cmp dword [next_free_page], PAGETABLE_POOL_END
    ja .exhausted

    push edi
    push ecx
    mov edi, eax
    xor ecx, ecx
.zero:
    mov dword [edi + ecx], 0
    add ecx, 4
    cmp ecx, 0x1000
    jb .zero
    pop ecx
    pop edi
    ret

.exhausted:
    ; Pula tablic stron wyczerpana -- zbyt duzy IDENTITY_MAP_GIB albo za mala
    ; pula. Diagnostyka przez port szeregowy (BIOS teletype juz niedostepny
    ; po przejsciu do trybu chronionego) i zatrzymanie.
    mov esi, msg_pt_exhausted
    call pm32_serial_print
    jmp pm32_halt

pm32_serial_print:
    push eax
    push edx
.next:
    mov al, [esi]
    or al, al
    jz .done
    inc esi
    mov dx, 0x3FD
.wait:
    in al, dx
    test al, 0x20
    jz .wait
    mov al, [esi - 1]
    mov dx, 0x3F8
    out dx, al
    jmp .next
.done:
    pop edx
    pop eax
    ret

pm32_halt:
    cli
.hang:
    hlt
    jmp .hang

msg_pt_exhausted: db "zboot-bios: BLAD -- pula tablic stron wyczerpana", 13, 10, 0

next_free_page: dd PAGETABLE_POOL_START
pml4_phys:      dd 0

; ----------------------------------------------------------------------------
; Buduje identity mapping stronami 2 MiB dla zakresu 0..IDENTITY_MAP_GIB GiB
; -- odpowiednik zbootpkg/paging.mapRegion2M po stronie UEFI. Adresy tej
; petli miesza sie w 32 bitach (IDENTITY_MAP_GIB=4 -> max adres 0xFFFFFFFF),
; wiec czysta arytmetyka 32-bitowa wystarcza.
pm32_build_identity_map:
    push eax
    push ebx
    push ecx
    push edx
    push esi
    push edi

    call pm32_alloc_page
    mov [pml4_phys], eax

    ; UWAGA: IDENTITY_MAP_GIB * 0x40000000 (4 GiB = 0x100000000) NIE miesci
    ; sie w 32 bitach -- porownywanie ebx z ta wartoscia jako imm32
    ; przepelnialoby sie do 0 i przerywalo petle po zerowej liczbie iteracji.
    ; Zamiast tego liczymy strony 2 MiB w DOL, w zmiennej pamieciowej (ecx
    ; jest w ciele petli uzywany jako rejestr roboczy, wiec nie nadaje sie
    ; na licznik trzymany przez cala petle).
    mov dword [im_remaining_pages], IDENTITY_MAP_GIB * 512
    xor ebx, ebx                       ; ebx = biezacy adres bazowy strony 2 MiB (identity: virt == phys)
.loop_2m:
    cmp dword [im_remaining_pages], 0
    jz .done

    ; --- PML4[0] -> PDPT (indeks PML4 zawsze 0 dla adresow < 512 GiB) ---
    mov edi, [pml4_phys]
    mov eax, [edi]
    test eax, 1
    jnz .have_pdpt
    call pm32_alloc_page
    mov ecx, eax
    or eax, 3                   ; present | writable
    mov [edi], eax
    mov eax, ecx
.have_pdpt:
    and eax, 0xFFFFF000
    mov esi, eax                ; esi = adres fizyczny PDPT

    ; --- PDPT[idx] -> PD ---
    mov eax, ebx
    shr eax, 30
    and eax, 0x1FF
    lea edi, [esi + eax*8]
    mov eax, [edi]
    test eax, 1
    jnz .have_pd
    call pm32_alloc_page
    mov ecx, eax
    or eax, 3
    mov [edi], eax
    mov eax, ecx
.have_pd:
    and eax, 0xFFFFF000
    mov esi, eax                 ; esi = adres fizyczny PD

    ; --- PD[idx] = strona 2 MiB (present | writable | PS/huge) ---
    mov eax, ebx
    shr eax, 21
    and eax, 0x1FF
    lea edi, [esi + eax*8]
    mov edx, ebx
    and edx, 0xFFE00000           ; wyrownanie do granicy 2 MiB
    or edx, 0x83
    mov [edi], edx
    mov dword [edi + 4], 0

    add ebx, 0x200000
    dec dword [im_remaining_pages]
    jmp .loop_2m

.done:
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

im_remaining_pages: dd 0

; ============================================================================
; 64-bit long mode -- ELF64, kopiowanie segmentow, mapowanie per-segment,
; BootInfo, skok do jadra. Odpowiednik zbootpkg/elf.nim + zbootpkg/paging.nim
; + zbootpkg/handoff.nim po stronie UEFI, tyle ze w asemblerze.
; ============================================================================
BITS 64
entry64:
    mov ax, SEL_DATA64
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov rsp, STACK64_TOP

    ; --- zapisz w BootInfo to, co juz znamy z fazy 16-bit ---
    mov rax, E820_BUFFER
    mov qword [BOOTINFO_ADDR + 0x00], rax      ; memoryMapAddr
    movzx eax, word [e820_count]
    imul eax, eax, E820_ENTRY_SIZE
    mov qword [BOOTINFO_ADDR + 0x08], rax      ; memoryMapSize (bajty)
    mov qword [BOOTINFO_ADDR + 0x10], E820_ENTRY_SIZE ; memoryMapDescSize

    ; --- framebuffer: wypelnione przez detect_vbe w fazie 16-bit (albo
    ;     zerami, jesli VBE niedostepne/nie znaleziono pasujacego trybu --
    ;     patrz obszerny komentarz przy detect_vbe) ---
    movzx eax, word [vbe_mode_number]
    test eax, eax
    jz .no_fb

    mov eax, [vbe_best_physbase]
    ; UWAGA: zapis do EAX zeruje automatycznie gorna polowe RAX (standardowe
    ; zachowanie x86-64 dla operacji 32-bitowych) -- RAX jest wiec juz
    ; poprawnym, w pelni wyzerowanym-z-gory 64-bitowym adresem fizycznym.
    mov qword [BOOTINFO_ADDR + 0x28], rax       ; fbBase

    movzx eax, word [vbe_best_pitch]
    movzx ecx, word [vbe_best_height]
    mul ecx                                      ; eax = pitch * height =~ fbSize
    mov qword [BOOTINFO_ADDR + 0x30], rax        ; fbSize

    movzx eax, word [vbe_best_width]
    mov dword [BOOTINFO_ADDR + 0x38], eax        ; fbWidth
    movzx eax, word [vbe_best_height]
    mov dword [BOOTINFO_ADDR + 0x3C], eax        ; fbHeight

    ; fbPixelsPerLine = BytesPerScanLine / bytesPerPixel, gdzie
    ; bytesPerPixel = ceil(bpp/8) -- WAZNE zaokraglenie w GORE: np. 15bpp
    ; faktycznie zajmuje 2 bajty/piksel w pamieci, nie 1 (obcięcie w dol
    ; dawaloby tu blednie podwojona "szerokosc" linii).
    movzx eax, byte [vbe_best_bpp]
    add eax, 7
    shr eax, 3
    mov ecx, eax                                  ; ecx = bytesPerPixel
    movzx eax, word [vbe_best_pitch]
    xor edx, edx
    div ecx                                        ; eax = pitch / bytesPerPixel
    mov dword [BOOTINFO_ADDR + 0x40], eax          ; fbPixelsPerLine

    movzx eax, byte [vbe_best_bgr]
    mov byte [BOOTINFO_ADDR + 0x44], al            ; fbBgr
    jmp .fb_done
.no_fb:
    mov qword [BOOTINFO_ADDR + 0x28], 0           ; fbBase
    mov qword [BOOTINFO_ADDR + 0x30], 0           ; fbSize
    mov dword [BOOTINFO_ADDR + 0x38], 0           ; fbWidth
    mov dword [BOOTINFO_ADDR + 0x3C], 0           ; fbHeight
    mov dword [BOOTINFO_ADDR + 0x40], 0           ; fbPixelsPerLine
    mov byte  [BOOTINFO_ADDR + 0x44], 0           ; fbBgr
.fb_done:
    mov byte  [BOOTINFO_ADDR + 0x45], 1        ; firmwareKind = 1 (BIOS)
    movzx eax, word [e820_count]
    mov dword [BOOTINFO_ADDR + 0x48], eax      ; e820EntryCount

    ; --- parsuj naglowek ELF64 pod KERNEL_STAGE_LINEAR ---
    mov rsi, KERNEL_STAGE_LINEAR

    cmp dword [rsi], 0x464C457F      ; magic "\x7FELF" (LE)
    jne elf_bad
    cmp byte [rsi + 4], 2             ; EI_CLASS == ELFCLASS64
    jne elf_bad

    mov rax, [rsi + 24]                ; e_entry
    mov [kernel_entry], rax
    mov [BOOTINFO_ADDR + 0x20], rax    ; kernelEntry (qword)

    movzx r8, word [rsi + 54]           ; e_phentsize
    movzx r9, word [rsi + 56]            ; e_phnum
    mov rax, [rsi + 32]                   ; e_phoff
    lea r10, [rsi + rax]                   ; r10 = wskaznik na tablice naglowkow programu

    ; --- pierwszy przebieg: policz lowestVaddr/highestEnd po PT_LOAD ---
    mov rax, 0xFFFFFFFFFFFFFFFF
    mov [lowest_vaddr], rax
    xor rax, rax
    mov [highest_end], rax

    xor rcx, rcx                          ; rcx = indeks segmentu
.scan_loop:
    cmp rcx, r9
    jae .scan_done
    mov rax, rcx
    mul r8
    lea rdx, [r10 + rax]                    ; rdx = wskaznik biezacego Phdr

    cmp dword [rdx + 0], 1                    ; p_type == PT_LOAD ?
    jne .scan_next

    mov rax, [rdx + 16]                        ; p_vaddr
    cmp rax, [lowest_vaddr]
    jae .no_new_low
    mov [lowest_vaddr], rax
.no_new_low:
    mov rax, [rdx + 16]                          ; p_vaddr
    add rax, [rdx + 40]                            ; + p_memsz
    cmp rax, [highest_end]
    jbe .no_new_high
    mov [highest_end], rax
.no_new_high:
.scan_next:
    inc rcx
    jmp .scan_loop
.scan_done:

    mov rax, [highest_end]
    sub rax, [lowest_vaddr]
    mov [span_bytes], rax
    cmp qword [span_bytes], 0
    je elf_bad

    mov qword [BOOTINFO_ADDR + 0x18], KERNEL_PHYS_BASE ; kernelBase

    ; --- drugi przebieg: skopiuj kazdy segment PT_LOAD i zmapuj go osobno ---
    xor rcx, rcx
.copy_loop:
    cmp rcx, r9
    jae .copy_done
    mov rax, rcx
    mul r8
    lea rdx, [r10 + rax]

    cmp dword [rdx + 0], 1
    jne .copy_next

    mov rax, [rdx + 16]                ; p_vaddr
    sub rax, [lowest_vaddr]
    add rax, KERNEL_PHYS_BASE
    mov r11, rax                        ; r11 = docelowy adres fizyczny segmentu

    mov rsi, [rdx + 8]                    ; p_offset
    add rsi, KERNEL_STAGE_LINEAR             ; rsi = zrodlo (offset w buforze)
    mov rdi, r11                              ; rdi = cel

    mov [rcx_save], rcx
    mov r12, [rdx + 32]                         ; p_filesz
    mov r13, [rdx + 40]                          ; p_memsz
    mov r14d, [rdx + 4]                           ; p_flags (offset 4 w Elf64_Phdr, u32 -- mov do r14d zeruje gorne 32 bity r14)

    ; kopiuj p_filesz bajtow
    mov rcx, r12
    cld
    rep movsb

    ; wyzeruj reszte (p_memsz - p_filesz), czyli .bss
    mov rax, r13
    sub rax, r12
    jz .no_bss
    mov rcx, rax
    xor al, al
    rep stosb
.no_bss:

    ; zmapuj ten segment stronami 4 KiB z uprawnieniami z p_flags
    mov rdi, [rdx + 16]                 ; virt = p_vaddr
    mov rsi, r11                          ; phys = docelowy adres fizyczny
    mov rdx, r13                            ; size = p_memsz (zaokraglone w map64_region4k)
    mov rcx, r14                              ; flags = p_flags
    call map64_kernel_segment

    mov rcx, [rcx_save]
.copy_next:
    inc rcx
    jmp .copy_loop
.copy_done:

    mov si, msg_long_mode_ok
    call serial_print64

    ; --- skok do jadra ---
    mov rdi, BOOTINFO_ADDR
    mov rax, [kernel_entry]
    jmp rax

elf_bad:
    mov si, msg_elf_bad
    call serial_print64
    jmp halt64

halt64:
    cli
.hang:
    hlt
    jmp .hang

rcx_save:      dq 0
kernel_entry:  dq 0
lowest_vaddr:  dq 0
highest_end:   dq 0
span_bytes:    dq 0

msg_long_mode_ok: db "zboot-bios: tryb dlugi, jadro zaladowane i zmapowane -- skok...", 13, 10, 0
msg_elf_bad:      db "zboot-bios: BLAD -- niepoprawny naglowek ELF64 jadra", 13, 10, 0

; SI (wskaznik 16-bitowy, ale bufory komunikatow leza w pierwszych 64 KiB,
; wiec RSI z zerowa gorna czescia dziala identycznie) -> ASCIIZ.
serial_print64:
    push rax
    push rdx
    push rsi
    movzx rsi, si
.next:
    mov al, [rsi]
    or al, al
    jz .done
    inc rsi
    mov dx, 0x3FD
.wait:
    in al, dx
    test al, 0x20
    jz .wait
    mov al, [rsi - 1]
    mov dx, 0x3F8
    out dx, al
    jmp .next
.done:
    pop rsi
    pop rdx
    pop rax
    ret

; ----------------------------------------------------------------------------
; Mapuje pojedynczy segment PT_LOAD stronami 4 KiB z uprawnieniami R/W/X
; wynikajacymi z p_flags ELF -- odpowiednik zbootpkg/paging.mapRegion4K +
; pageFlags + mapKernelSegments (tam rozbite na kilka proc, tutaj polaczone
; w jedna procedure, bo wywolywana jest raz na segment z ta sama pula
; tablic co identity mapping z fazy 32-bit -- PML4 jest wspoldzielony,
; wiec nowe wpisy po prostu rozszerzaja juz aktywne odwzorowanie bez
; potrzeby przeladowania CR3).
;
; Wejscie: RDI = virt (p_vaddr), RSI = phys (docelowy adres fizyczny),
;          RDX = size (p_memsz, zaokraglane tutaj w gore do 4 KiB),
;          RCX = p_flags (PF_X=1, PF_W=2, PF_R=4).
map64_kernel_segment:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10

    ; oblicz bity uprawnien wpisu PTE z p_flags (PF_R jest ignorowane --
    ; na x86-64 obecna strona jest zawsze czytelna)
    mov r8, 1                       ; present
    test rcx, 2                     ; PF_W ?
    jz .no_write
    or r8, 2                        ; writable
.no_write:
    test rcx, 1                     ; PF_X ?
    jnz .no_nx
    mov r9, 1
    shl r9, 63
    or r8, r9                       ; NX
.no_nx:
    mov [seg_flags], r8

    ; zaokraglij size w gore do 4 KiB
    add rdx, 0xFFF
    and rdx, ~0xFFF
    mov [seg_size], rdx

    and rdi, ~0xFFF                 ; wyrownaj virt w dol do 4 KiB
    and rsi, ~0xFFF                 ; wyrownaj phys w dol do 4 KiB
    mov [seg_virt], rdi
    mov [seg_phys], rsi

    xor r10, r10                    ; przesuniecie od poczatku segmentu
.page_loop:
    cmp r10, [seg_size]
    jae .page_done

    mov rdi, [seg_virt]
    add rdi, r10                    ; biezacy adres wirtualny strony

    call map64_walk_or_create        ; -> RAX = wskaznik na wpis PTE (u64*)

    mov rbx, [seg_phys]
    add rbx, r10
    and rbx, 0xFFFFFFFFFFFFF000
    or rbx, [seg_flags]
    mov [rax], rbx

    add r10, 0x1000
    jmp .page_loop
.page_done:

    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

seg_flags: dq 0
seg_size:  dq 0
seg_virt:  dq 0
seg_phys:  dq 0

; ----------------------------------------------------------------------------
; Dla adresu wirtualnego w RDI: przechodzi PML4->PDPT->PD->PT, tworzac
; (przydzielajac z puli tablic stron) kazdy brakujacy poziom po drodze.
; Zwraca w RAX adres WPISU PT (nie strony) dla tego adresu -- wolajacy sam
; wpisuje docelowy adres fizyczny + flagi.
map64_walk_or_create:
    push rbx
    push rcx
    push rdx

    ; pml4_phys jest zmienna 32-bitowa (dd) ustawiona w fazie 32-bit --
    ; `mov eax, [...]` na 32-bitowy rejestr docelowy automatycznie zeruje
    ; gorne 32 bity RAX (regula x86-64), wiec ponizej mamy juz poprawny
    ; pelny 64-bitowy adres fizyczny bez dodatkowego maskowania.
    mov eax, [pml4_phys]

    mov rcx, rdi
    shr rcx, 39
    and rcx, 0x1FF
    lea rdx, [rax + rcx*8]
    call map64_get_or_create_table
    mov rax, rbx

    mov rcx, rdi
    shr rcx, 30
    and rcx, 0x1FF
    lea rdx, [rax + rcx*8]
    call map64_get_or_create_table
    mov rax, rbx

    mov rcx, rdi
    shr rcx, 21
    and rcx, 0x1FF
    lea rdx, [rax + rcx*8]
    call map64_get_or_create_table
    mov rax, rbx

    mov rcx, rdi
    shr rcx, 12
    and rcx, 0x1FF
    lea rax, [rax + rcx*8]              ; adres WPISU PT (nie tabeli nizej)

    pop rdx
    pop rcx
    pop rbx
    ret

; Wejscie: RDX = wskaznik na wpis nadrzedny (PML4E/PDPTE/PDE).
; Wyjscie: RBX = adres fizyczny tabeli nizszego poziomu (utworzonej w razie
; braku -- present|writable, permisywne posrednie wpisy; faktyczne
; uprawnienia R/W/X sa wymuszane dopiero na koncowym wpisie PT).
map64_get_or_create_table:
    mov rax, [rdx]
    test rax, 1
    jnz .have
    call map64_alloc_page
    mov rbx, rax
    or rax, 3                    ; present | writable
    mov [rdx], rax
    ret
.have:
    mov rbx, rax
    and rbx, 0xFFFFFFFFFFFFF000
    ret

; Przydziela strone 4 KiB z tej samej puli "bump" co pm32_alloc_page (ta sama
; pamiec, teraz dostepna z pelna arytmetyka 64-bit) i zeruje ja.
map64_alloc_page:
    push rcx
    push rdi

    mov eax, [next_free_page]
    add dword [next_free_page], 0x1000
    cmp dword [next_free_page], PAGETABLE_POOL_END
    ja .exhausted

    mov rdi, rax
    mov rcx, 512
    xor rax, rax
    push rdi
    rep stosq
    pop rax

    pop rdi
    pop rcx
    ret

.exhausted:
    mov si, msg_pt_exhausted64
    call serial_print64
    jmp halt64

msg_pt_exhausted64: db "zboot-bios: BLAD -- pula tablic stron wyczerpana (faza 64-bit)", 13, 10, 0

; ----------------------------------------------------------------------------
; Dopelnienie stage2 do calkowitego rozmiaru STAGE2_SECTORS * 512 bajtow --
; scripts/make-bios-image.py sprawdza, ze wynikowy plik miesci sie w tym
; budzecie i sam go dopelnia, ale trzymamy sie tu tej samej stalej dla
; jasnosci (i zeby `nasm -f bin` od razu dal plik o oczekiwanym rozmiarze
; przy typowej zawartosci -- ostateczne, twarde dopelnienie i tak robi
; skrypt budujacy obraz dysku).
