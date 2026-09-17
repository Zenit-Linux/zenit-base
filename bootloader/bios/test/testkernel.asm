BITS 64

global _start
section .text
_start:
    mov rsi, msg_banner
    call serial_print

    mov rsi, msg_firmware_kind
    call serial_print
    movzx rax, byte [rdi + 0x45]
    mov cl, 4
    call serial_print_hex

    mov rsi, msg_kernel_base
    call serial_print
    mov rax, [rdi + 0x18]
    mov cl, 60
    call serial_print_hex

    mov rsi, msg_kernel_entry
    call serial_print
    mov rax, [rdi + 0x20]
    mov cl, 60
    call serial_print_hex

    mov rsi, msg_e820_count
    call serial_print
    mov eax, [rdi + 0x48]
    mov cl, 28
    call serial_print_hex

    ; --- sprawdz uprawnienia stron faktycznie ustawione przez zboot-bios ---
    mov rdi, text_probe_byte
    call walk_pte
    mov [pte_text], rax

    mov rdi, data_probe_byte
    call walk_pte
    mov [pte_data], rax

    mov rsi, msg_pte_text
    call serial_print
    mov rax, [pte_text]
    mov cl, 60
    call serial_print_hex

    mov rsi, msg_pte_data
    call serial_print
    mov rax, [pte_data]
    mov cl, 60
    call serial_print_hex

    ; .text: present(bit0)=1 oraz NX(bit63)=0 (segment wykonywalny)
    mov rax, [pte_text]
    test rax, 1
    jz .fail
    bt rax, 63
    jc .fail

    ; .data: present=1, writable(bit1)=1, NX(bit63)=1 (segment danych)
    mov rax, [pte_data]
    test rax, 1
    jz .fail
    test rax, 2
    jz .fail
    bt rax, 63
    jnc .fail

    mov rsi, msg_pass
    call serial_print
    mov al, 0x10
    call qemu_exit

.fail:
    mov rsi, msg_fail
    call serial_print
    mov al, 0x11
    call qemu_exit

; ----------------------------------------------------------------------------
; AL = kod; wychodzi z QEMU przez urzadzenie isa-debug-exit (io 0xF4).
qemu_exit:
    mov dx, 0xF4
    out dx, al
.hang:
    hlt
    jmp .hang

; ----------------------------------------------------------------------------
; RDI = adres wirtualny -> RAX = surowa wartosc wpisu PTE (4 KiB, bez
; obslugi PS na poziomie PD -- adresy testowe naleza do segmentow jadra,
; ktore zboot-bios zawsze mapuje stronami 4 KiB, nigdy 2 MiB).
walk_pte:
    push rcx
    mov rax, cr3
    and rax, 0xFFFFFFFFFFFFF000

    mov rcx, rdi
    shr rcx, 39
    and rcx, 0x1FF
    mov rax, [rax + rcx*8]
    and rax, 0xFFFFFFFFFFFFF000

    mov rcx, rdi
    shr rcx, 30
    and rcx, 0x1FF
    mov rax, [rax + rcx*8]
    and rax, 0xFFFFFFFFFFFFF000

    mov rcx, rdi
    shr rcx, 21
    and rcx, 0x1FF
    mov rax, [rax + rcx*8]
    and rax, 0xFFFFFFFFFFFFF000

    mov rcx, rdi
    shr rcx, 12
    and rcx, 0x1FF
    mov rax, [rax + rcx*8]

    pop rcx
    ret

; ----------------------------------------------------------------------------
; RSI -> ASCIIZ, wypisywany na COM1 (0x3F8).
serial_print:
    push rax
    push rbx
    push rdx
.next:
    mov bl, [rsi]
    or bl, bl
    jz .done
    inc rsi
    mov dx, 0x3FD
.wait:
    in al, dx
    test al, 0x20
    jz .wait
    mov al, bl
    mov dx, 0x3F8
    out dx, al
    jmp .next
.done:
    pop rdx
    pop rbx
    pop rax
    ret

; RAX = wartosc, CL = bit startowy (60=64-bit/16 cyfr, 28=32-bit/8 cyfr,
; 4=8-bit/2 cyfry) -- wypisuje kolejne cyfry szesnastkowe + CRLF.
serial_print_hex:
    push rax
    push rbx
    push rcx
    mov rbx, rax
.loop:
    mov rax, rbx
    shr rax, cl
    and rax, 0xF
    cmp al, 10
    jae .letter
    add al, '0'
    jmp .emit
.letter:
    add al, 'A' - 10
.emit:
    call serial_putc_al
    sub cl, 4
    jns .loop
    mov al, 13
    call serial_putc_al
    mov al, 10
    call serial_putc_al
    pop rcx
    pop rbx
    pop rax
    ret

; AL = znak do wyslania.
serial_putc_al:
    push rbx
    push rdx
    mov bl, al
    mov dx, 0x3FD
.wait:
    in al, dx
    test al, 0x20
    jz .wait
    mov al, bl
    mov dx, 0x3F8
    out dx, al
    pop rdx
    pop rbx
    ret

; ----------------------------------------------------------------------------
; Bajt w segmencie .text (R+X oczekiwane, bez W, bez ustawionego NX) --
; celowo NIE jest wykonywany (lezy za bezwarunkowa petla .hang powyzej w
; kazdej sciezce), sluzy wylacznie jako adres do sprawdzenia PTE.
text_probe_byte: db 0x90

; ----------------------------------------------------------------------------
section .rodata
msg_banner:        db "testkernel: wejscie higher-half osiagniete (RDI=BootInfo*)", 13, 10, 0
msg_firmware_kind:  db "testkernel: firmwareKind = 0x", 0
msg_kernel_base:     db "testkernel: kernelBase   = 0x", 0
msg_kernel_entry:     db "testkernel: kernelEntry  = 0x", 0
msg_e820_count:        db "testkernel: e820EntryCount = 0x", 0
msg_pte_text:           db "testkernel: PTE(.text) = 0x", 0
msg_pte_data:            db "testkernel: PTE(.data) = 0x", 0
msg_pass:                 db "testkernel: WYNIK = PASS", 13, 10, 0
msg_fail:                  db "testkernel: WYNIK = FAIL", 13, 10, 0

; ----------------------------------------------------------------------------
section .data
; Bajt w segmencie danych (R+W oczekiwane, .data ma PF_R|PF_W, bez PF_X).
data_probe_byte: db 0x42
pte_text:        dq 0
pte_data:        dq 0
