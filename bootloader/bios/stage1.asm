BITS 16
ORG 0x7C00

; Ulozenie stage2 na dysku (patrz takze scripts/make-bios-image.py, ktory
; MUSI uzywac tych samych stalych przy budowie obrazu dysku):
;   LBA 0                                 -> ten plik (stage1, MBR)
;   LBA STAGE2_LBA_START .. +SECTORS-1    -> stage2.bin (dopelniony zerami)
STAGE2_SEGMENT      equ 0x0000
STAGE2_OFFSET        equ 0x8000
STAGE2_LBA_START      equ 1
STAGE2_SECTORS         equ 32          ; 32 * 512 B = 16 KiB budzetu na stage2

; ----------------------------------------------------------------------------
start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00          ; stos rosnie w dol ponizej MBR -- wolny obszar
    sti

    mov [boot_drive], dl    ; BIOS przekazuje numer dysku rozruchowego w DL

    mov si, msg_stage1
    call print_string

    ; --- sprawdz obecnosc rozszerzen INT 13h (funkcja 41h, "Check Extensions
    ; Present") -- bez nich funkcja 42h ponizej nie jest bezpieczna do uzycia.
    mov ah, 0x41
    mov bx, 0x55AA
    mov dl, [boot_drive]
    int 0x13
    jc .no_lba
    cmp bx, 0xAA55
    jne .no_lba

    ; --- wczytaj stage2 przez rozszerzony odczyt LBA (funkcja 42h) ---
    mov si, dap
    mov ah, 0x42
    mov dl, [boot_drive]
    int 0x13
    jc disk_error

    mov si, msg_ok
    call print_string

    mov dl, [boot_drive]    ; przekaz numer dysku dalej, do stage2
    jmp STAGE2_SEGMENT:STAGE2_OFFSET

.no_lba:
    mov si, msg_no_lba
    call print_string
    jmp halt

disk_error:
    mov si, msg_disk_err
    call print_string
    ; spadamy do halt

halt:
    cli
.hang:
    hlt
    jmp .hang

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
boot_drive: db 0

; Disk Address Packet dla INT 13h/AH=42h (rozszerzony odczyt LBA) -- format
; opisany w specyfikacji "El Torito"/BIOS INT13h Extensions:
;   +0  u8  rozmiar pakietu (16)
;   +1  u8  zarezerwowane (0)
;   +2  u16 liczba sektorow do odczytu
;   +4  u16 offset bufora docelowego
;   +6  u16 segment bufora docelowego
;   +8  u64 poczatkowy LBA
align 4
dap:
    db 0x10
    db 0
    dw STAGE2_SECTORS
    dw STAGE2_OFFSET
    dw STAGE2_SEGMENT
    dq STAGE2_LBA_START

msg_stage1:   db "zboot-bios: stage1", 13, 10, 0
msg_ok:       db "zboot-bios: stage2 wczytany, przekazuje sterowanie...", 13, 10, 0
msg_no_lba:   db "zboot-bios: BLAD -- brak rozszerzen INT13h LBA na tym BIOS", 13, 10, 0
msg_disk_err: db "zboot-bios: BLAD odczytu dysku (stage2)", 13, 10, 0

; ----------------------------------------------------------------------------
; Dopelnienie do 510 bajtow + sygnatura rozruchowa 0x55AA (wymagana przez BIOS).
times 510 - ($ - $$) db 0
dw 0xAA55
