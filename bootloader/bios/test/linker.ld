ENTRY(_start)

PHDRS
{
    text PT_LOAD FLAGS(5); /* R+X */
    data PT_LOAD FLAGS(6); /* R+W */
}

SECTIONS
{
    . = 0xFFFFFFFF80100000;

    .text : {
        *(.text)
    } :text

    . = ALIGN(0x1000);

    .rodata : {
        *(.rodata)
    } :data

    .data : {
        *(.data)
    } :data

    .bss : {
        *(.bss)
        *(COMMON)
    } :data

    /DISCARD/ : {
        *(.comment)
        *(.eh_frame)
        *(.note*)
    }
}
