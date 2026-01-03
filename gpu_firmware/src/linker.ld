ENTRY(_start)

MEMORY
{
    /* Embedded instruction memory */
    imem (rx): ORIGIN = 0x80000000, LENGTH = 16K

    /* Embedded data memory */
    dmem (rw): ORIGIN = 0x80004000, LENGTH = 3K

    /* External synchronous dynamic random access memory */
    sdram (rw): ORIGIN = 0x80008000, LENGTH = 80K
}

SECTIONS
{
  .text : {
    KEEP(*(.text.start))
    *(.text*)
  } > imem

  .rodata : {
    *(.rodata .rodata.*)
  } > dmem

  .data : ALIGN(16) {
      *(.data .data.*)
  } > dmem

  PROVIDE(__bss_start = .);
  .sbss : ALIGN(16) {
    *(.sbss .sbss.*)
  } > sdram

  .bss : ALIGN(16) {
    *(.bss .bss.*)
  } > sdram
  PROVIDE(__bss_end = .);

  PROVIDE(__malloc_buffer = .);
}
