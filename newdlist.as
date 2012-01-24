// compact display list generation

//#define MAX_VBLANK_CYCLES 2120

/*
// 54 cycles
// 41 bytes
zp_writer_rom:
    lda #00 // 0        2 * 8
    sta PPU.IO      //  4 * 8
    lda #00 // 1
    sta PPU.IO
    lda #00 // 2
    sta PPU.IO
    lda #00 // 3
    sta PPU.IO
    lda #00 // 4
    sta PPU.IO
    lda #00 // 5
    sta PPU.IO
    lda #00 // 6
    sta PPU.IO
    lda #00 // 7
    sta PPU.IO
    rts             //  6
zp_writer_rom_end:
*/

#align 256
advancetab:
#incbin "advancetab.bin"    // first 0x100 is +2, up to +10

/*
rangetab:
#incbin "rangetab.bin"
*/

// ******** init

// ******** buffer maintenance

// ******** execution

// ******** command utils

// ******** commands

// ******** runtime command utils

// 6 cycles
inline cu_update_data_ptr(bytes)
{
    lda advancetab+( ( (bytes)-2)*0x100), Y
    tay
}

// 6 cycles
inline cu_update_data_ptr_lines(lines)
{
    cu_update_data_ptr(2+lines)
}

// 16 cycles
inline cu_set_addr(page)
{
    //lda ($100*page), Y
    //sta $2006
    //lda ($100*page)+1, Y
    //sta $2006
}

// 24 cycles
inline cu_set_addr_prep(page)
{
    //lda ($100*page), Y
    //sta $2006
    //ldx ($100*page)+1, Y
    //stx $2006

    // dummy read
    lda $2007

    // another set for the update
    sta $2006
}

// 8 cycles
inline cu_op_line(page, op, line)
{
    lda ($100*page)+2+line, Y
    op $2007
}

// 8 cycles
inline cu_write_line(page, line)
{
    lda ($100*page)+2+line, Y
    sta $2007
}

// 11 cycles
inline cu_op_sta_line(page, op, line, lines)
{
    cu_op_line(page, op, line)
    sta zp_immed_0+( ( (8-lines)+line)*5)
}

// 11 cycles
inline cu_updt_line(page, line, op)
{
    cu_op_line(page, op, line)
    sta zp_immed_0+(line*5)
}

// 8 cycles
inline cu_copy_line(page, line)
{
    lda $2007
    sta zp_immed_0+(line*5)
}

// 3+6*lines+6 cycles
inline cu_jmp_zpwr_lines(lines)
{
    jmp zp_writer+( (8-lines)*5)
}

#tell.bankoffset
#include "codegen.as"
#tell.bankoffset
