// threaded display list generation

#define MAX_VBLANK_CYCLES 2120

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

#align 256
advancetab:
#incbin "advancetab.bin"    // first 0x100 is +1, up to +3

rangetab:
#incbin "rangetab.bin"

// ******** init
function dlist_wrap()
{
    ldx #lo(dlist-1)
    txs
}

function init_dlist()
{
    // load zp_writer
    ldx #(zp_writer_rom_end-zp_writer_rom)-1
    do
    {
        lda zp_writer_rom, X
        sta zp_writer, X
        dex
    } while (not minus)

    // init current dlist status
    ldx #lo(dlist)
    stx dlist_next_cmd_read
    stx dlist_cmd_end
    stx dlist_next_cmd_write

    lda #0
    sta dlist_data_read
    sta dlist_data_write

    assign_16i(dlist_cycles_left, MAX_VBLANK_CYCLES)
    assign(dlist_reset_cycles, #0)

    // dlist wrap catcher
    assign_16i(0x100, dlist_wrap-1)

    // fill flip_nametable
    ldx #0x10
    ldy #0
    lda #0
    clc
    do {
        tya
        sta flip_nametable+0x10, Y
        eor #0x10
        sta flip_nametable, Y
        iny
        dex
    } while (not zero)
}

// ******** execution
function dlist_end_incomplete()
{
    lda #1
    sta dlist_reset_cycles

    // back up
    tsx
    dex
    dex
    txs

dlist_end_complete:
    vram_clear_address()
    ppu_ctl1_assign(#CR_BACKVISIBLE)    // reenable rendering

    tsx
    inx
    stx dlist_next_cmd_read

    sty dlist_data_read

    ldx dlist_cmd_end
    lda dlist_cmd_copy+0
    sta 0x100, X
    lda dlist_cmd_copy+1
    sta 0x101, X

    ldx dlist_orig_S
    txs
}

function process_dlist()
{
#tell.bankoffset
    ppu_ctl1_assign(#0) // disable rendering

    ldx dlist_cmd_end
    lda 0x100, X
    sta dlist_cmd_copy+0
    lda 0x101, X
    sta dlist_cmd_copy+1

    lda #lo(dlist_end_incomplete-1)
    sta 0x100, X
    lda #hi(dlist_end_incomplete-1)
    sta 0x101, X

    tsx
    stx dlist_orig_S

    ldy dlist_data_read

    ldx dlist_next_cmd_read
    dex
    txs
}

function finalize_dlist()
{
    ldy dlist_next_cmd_write

    lda #lo(dlist_end_complete-1)
    sta 0x100, Y
    lda #hi(dlist_end_complete-1)
    sta 0x101, Y
    iny
    iny

    if (zero)
    {
        ldy #lo(dlist)
    }
    sty dlist_next_cmd_write
    sty dlist_cmd_end
}

// ******** command utils

// A = cmd-1 low, X = cmd-1 high
// returns data offset in X
function noreturn add_command()
{
    sta tmp_addr+0
    stx tmp_addr+1

add_loop:
    // wait for space to free up
    ldy dlist_next_cmd_write
    cpy dlist_next_cmd_read
    bne space_free
    // if we're at the end, queue is empty
    cpy dlist_cmd_end
    bne add_loop

space_free:

    sty dlist_next_cmd_write

    // get cycle count
    ldy #0

    lsr dlist_reset_cycles
    if (carry)
    {
        sec
        lda #lo(MAX_VBLANK_CYCLES)
        sbc (tmp_addr), Y
        sta dlist_cycles_left+0
        lda #hi(MAX_VBLANK_CYCLES)
        sbc #0
        sta dlist_cycles_left+1

 can_add_command:
        ldy dlist_next_cmd_write

        lda tmp_addr+0
        sta 0x100, Y
        txa
        sta 0x101, Y
        iny
        iny

        if (zero)
        {
            ldy #lo(dlist)
        }
        sty dlist_next_cmd_write

        ldx dlist_data_write

        rts
    }

    sec
    lda dlist_cycles_left+0
    sbc (tmp_addr), Y
    sta dlist_cycles_left+0
    lda dlist_cycles_left+1
    sbc #0
    sta dlist_cycles_left+1

    bpl can_add_command

    // otherwise we need to polish off the last dlist
    finalize_dlist()

    lda #lo(MAX_VBLANK_CYCLES)
    sta dlist_cycles_left+0
    lda #hi(MAX_VBLANK_CYCLES)
    sta dlist_cycles_left+1

    lda #0
    sta dlist_reset_cycles

    jmp add_loop
}

// X = data offset
inline finalize_command(rows)
{
    lda advancetab+( (rows-1)*0x100), X
    sta dlist_data_write

    ldy dlist_next_cmd_write
    sty dlist_cmd_end
}

inline store_address()
{
    lda cmd_addr+1
    sta dlist_data_0, X
    lda cmd_addr+0
    sta dlist_data_1, X
}

// ******** commands
function cmd_tile_clear()
{
    lda #lo(rt_clr_8_lines_cycles)
    ldx #hi(rt_clr_8_lines_cycles)

    add_command()
    store_address()
    finalize_command(1)
}

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

#include "codegen.as"
