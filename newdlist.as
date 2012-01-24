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
#incbin "advancetab.bin"    // first 0x100 is +1, up to +3

rangetab:
#incbin "rangetab.bin"

// ******** init
function init_dlist() {}

// ******** buffer maintenance

// ******** execution
function process_dlist() {}

// ******** command utils

// ******** commands
function cmd_tile_clear() {}
function cmd_tile_copy() {}
function cmd_set_lines() {}
function cmd_clr_lines() {}
function cmd_tile_cache_write() {}
function cmd_tile_cache_write_lines() {}
function cmd_X_update_lines() {}
function cmd_X_copy_all_lines() {}
function cmd_set_all_lines() {}
function dlist_finish_frame() {}

// ******** runtime command utils

// 6 cycles
inline cu_update_data_ptr(rows)
{
    lda advancetab+( ( (rows)-1)*0x100), Y
    tay
}

// 16 cycles
inline cu_set_addr()
{
    lda dlist_data_0, Y
    sta $2006
    ldx dlist_data_1, Y
    stx $2006
}

// 24 cycles
inline cu_set_addr_prep(page)
{
    cu_set_addr()

    // dummy read
    lda $2007

    // another set for the update
    sta $2006
}

// 8 cycles
inline cu_op_line(op, offset)
{
    lda offset, Y
    op $2007
}

// 8 cycles
inline cu_write_line(offset)
{
    lda offset, Y
    sta $2007
}

// 11 cycles
inline cu_op_sta_line(op, offset, line, lines)
{
    cu_op_line(op, offset)
    sta zp_immed_0+( ( (8-lines)+line)*5)
}

// 11 cycles
inline cu_updt_line(op, offset, line)
{
    cu_op_line(op, offset)
    sta zp_immed_0+(line*5)
}

// 7 cycles
inline cu_copy_line(line)
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
