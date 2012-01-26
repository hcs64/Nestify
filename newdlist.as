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

#include "codegen.as"

byte bytes_to_rows[10] = {
    0,
    hi(advancetab), //1 = 1
    hi(advancetab), //2
    hi(advancetab), //3
    hi(advancetab+0x100),   // 4 = 2
    hi(advancetab+0x100),   // 5
    hi(advancetab+0x100),   // 6
    hi(advancetab+0x200),   // 7 = 3
    hi(advancetab+0x200),   // 8
    hi(advancetab+0x200),   // 9
}

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
}

// ******** execution
function noreturn dlist_end_incomplete()
{
    vram_clear_address()
    ppu_ctl1_assign(#CR_BACKVISIBLE)    // reenable rendering

    lda #1
    sta dlist_reset_cycles

    // back up
    tsx
    dex
    stx dlist_next_cmd_read

    inc_16(incomplete_vblanks)

    jmp dlist_end_common
}

function dlist_end_complete()
{
    vram_clear_address()
    ppu_ctl1_assign(#CR_BACKVISIBLE)    // reenable rendering

    tsx
    inx

    if (equal)
    {
        ldx #lo(dlist)
    }

    stx dlist_next_cmd_read

    inc_16(complete_vblanks)

dlist_end_common:
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
}

// ******** command utils

// A = cmd-1 low, X = cmd-1 high
// returns data offset in X
function noreturn add_command()
{
    sta tmp_addr+0
    stx tmp_addr+1

retry_add:
    ldy dlist_next_cmd_write
    cpy dlist_next_cmd_read
    bne enough_space
    cpy dlist_cmd_end
    beq enough_space


    lda #0
    sta nmi_hit
    do
    {
        lda nmi_hit
    } while (zero)

    lda dlist_reset_cycles
    if (not zero)
    {
        inc_16(stuck_cnt)
    }
    jmp retry_add

enough_space:
    sty dlist_cmd_end

    // get cycle count
    ldy #0

    lsr dlist_reset_cycles
    if (carry)
    {
        // Reset cycles. Assume the last command may not have been
        // exposed in time to be executed, so count it against the
        // current dlist.
        sec
        lda #lo(MAX_VBLANK_CYCLES)
        sbc last_cmd_cycles
        sta dlist_cycles_left+0
        lda #hi(MAX_VBLANK_CYCLES)
        sbc #0
        sta dlist_cycles_left+1

    }

    sec
    lda dlist_cycles_left+0
    sbc [tmp_addr], Y
    sta dlist_cycles_left+0
    lda dlist_cycles_left+1
    sbc #0
    sta dlist_cycles_left+1

    bmi out_of_cycles

    lda [tmp_addr], Y
    sta last_cmd_cycles

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

out_of_cycles:

    // otherwise we need to polish off the last dlist
    finalize_dlist()

    lda #lo(MAX_VBLANK_CYCLES)
    sta dlist_cycles_left+0
    lda #hi(MAX_VBLANK_CYCLES)
    sta dlist_cycles_left+1

    lda #0
    sta dlist_reset_cycles

    jmp retry_add
}

// X = data offset
inline cmd_advance(rows)
{
    lda advancetab+( (rows-1)*0x100), X
    sta dlist_data_write
}

inline cmd_advance_lines()
{
    ldy cmd_lines
    lda bytes_to_rows+2, Y
    sta tmp_addr+1
    stx tmp_addr+0
    ldy #0
    lda [tmp_addr], Y
    sta dlist_data_write
}

inline store_address()
{
    lda cmd_addr+1
    sta dlist_data_0, X
    lda cmd_addr+0
    sta dlist_data_1, X
}

inline store_address_flip()
{
    lda cmd_addr+1
    eor #$10
    sta dlist_data_0, X
    lda cmd_addr+0
    sta dlist_data_1, X
}

inline store_line_address()
{
    lda cmd_addr+1
    sta dlist_data_0, X
    lda cmd_addr+0
    ora cmd_start
    sta dlist_data_1, X
}

inline copy_byte_of_8(line)
{
    lda cmd_byte+line
    sta dlist_data_0+( ( (1+line) - ( ( (1+line) / 3) * 3))*0x100)+( (1+line)/3), X
}

inline copy_byte(line)
{
    lda cmd_byte+line, Y
    sta dlist_data_0+( ( (2+line) - ( ( (2+line) / 3) * 3))*0x100)+( (2+line)/3), X
}

inline copy_cache_byte_of_8(cache_page, line)
{
    lda cache_page, Y
    sta dlist_data_0+( ( (1+line) - ( ( (1+line) / 3) * 3))*0x100)+( (1+line)/3), X
}

inline copy_cache_byte(cache_page, line)
{
    lda cache_page, Y
    sta dlist_data_0+( ( (2+line) - ( ( (2+line) / 3) * 3))*0x100)+( (2+line)/3), X
}

// ******** commands
function cmd_tile_clear()
{
    lda #lo(rt_clr_8_lines_cycles)
    ldx #hi(rt_clr_8_lines_cycles)

    add_command()
    store_address()
    cmd_advance(1)
}

function cmd_tile_copy()
{
    lda #lo(rt_copy_tile_cycles)
    ldx #hi(rt_copy_tile_cycles)

    add_command()
    store_address_flip()
    cmd_advance(1)
}

byte cmd_set_lines_tab_0[39] = { lo(rt_set_1_lines_cycles), lo(rt_set_2_lines_cycles), lo(rt_set_3_lines_cycles), lo(rt_set_4_lines_cycles), lo(rt_set_5_lines_cycles), lo(rt_set_6_lines_cycles), lo(rt_set_7_lines_cycles), lo(rt_set_8_lines_0_cycles), lo(rt_set_8_lines_1_cycles), lo(rt_set_8_lines_2_cycles), lo(rt_set_8_lines_3_cycles), lo(rt_set_8_lines_4_cycles), lo(rt_set_8_lines_5_cycles), lo(rt_set_8_lines_6_cycles), lo(rt_set_8_lines_7_cycles), lo(rt_set_8_lines_8_cycles), lo(rt_set_8_lines_9_cycles), lo(rt_set_8_lines_10_cycles), lo(rt_set_8_lines_11_cycles), lo(rt_set_8_lines_12_cycles), lo(rt_set_8_lines_13_cycles), lo(rt_set_8_lines_14_cycles), lo(rt_set_8_lines_15_cycles), lo(rt_set_8_lines_16_cycles), lo(rt_set_8_lines_17_cycles), lo(rt_set_8_lines_18_cycles), lo(rt_set_8_lines_19_cycles), lo(rt_set_8_lines_20_cycles), lo(rt_set_8_lines_21_cycles), lo(rt_set_8_lines_22_cycles), lo(rt_set_8_lines_23_cycles), lo(rt_set_8_lines_24_cycles), lo(rt_set_8_lines_25_cycles), lo(rt_set_8_lines_26_cycles), lo(rt_set_8_lines_27_cycles), lo(rt_set_8_lines_28_cycles), lo(rt_set_8_lines_29_cycles), lo(rt_set_8_lines_30_cycles), lo(rt_set_8_lines_31_cycles), }

byte cmd_set_lines_tab_1[39] = { hi(rt_set_1_lines_cycles), hi(rt_set_2_lines_cycles), hi(rt_set_3_lines_cycles), hi(rt_set_4_lines_cycles), hi(rt_set_5_lines_cycles), hi(rt_set_6_lines_cycles), hi(rt_set_7_lines_cycles), hi(rt_set_8_lines_0_cycles), hi(rt_set_8_lines_1_cycles), hi(rt_set_8_lines_2_cycles), hi(rt_set_8_lines_3_cycles), hi(rt_set_8_lines_4_cycles), hi(rt_set_8_lines_5_cycles), hi(rt_set_8_lines_6_cycles), hi(rt_set_8_lines_7_cycles), hi(rt_set_8_lines_8_cycles), hi(rt_set_8_lines_9_cycles), hi(rt_set_8_lines_10_cycles), hi(rt_set_8_lines_11_cycles), hi(rt_set_8_lines_12_cycles), hi(rt_set_8_lines_13_cycles), hi(rt_set_8_lines_14_cycles), hi(rt_set_8_lines_15_cycles), hi(rt_set_8_lines_16_cycles), hi(rt_set_8_lines_17_cycles), hi(rt_set_8_lines_18_cycles), hi(rt_set_8_lines_19_cycles), hi(rt_set_8_lines_20_cycles), hi(rt_set_8_lines_21_cycles), hi(rt_set_8_lines_22_cycles), hi(rt_set_8_lines_23_cycles), hi(rt_set_8_lines_24_cycles), hi(rt_set_8_lines_25_cycles), hi(rt_set_8_lines_26_cycles), hi(rt_set_8_lines_27_cycles), hi(rt_set_8_lines_28_cycles), hi(rt_set_8_lines_29_cycles), hi(rt_set_8_lines_30_cycles), hi(rt_set_8_lines_31_cycles), }

function cmd_set_lines()
{
    ldy cmd_lines
    cpy #8
    if (equal)
    {
        lda cmd_addr+1
        clc
        adc #8
        tay
    }

    lda cmd_set_lines_tab_0-1, Y
    ldx cmd_set_lines_tab_1-1, Y

    add_command()

    ldy cmd_lines
    lda cmd_set_lines_jmptab_0, Y
    sta tmp_addr+0
    lda cmd_set_lines_jmptab_1, Y
    sta tmp_addr+1

    ldy cmd_start

    store_line_address()

    jmp [tmp_addr]

 cmd_set_8_lines:
    lda cmd_addr+0
    sta dlist_data_0, X

    copy_byte_of_8(0)
    copy_byte_of_8(1)
    copy_byte_of_8(2)
    copy_byte_of_8(3)
    copy_byte_of_8(4)
    copy_byte_of_8(5)
    copy_byte_of_8(6)
    copy_byte_of_8(7)

    cmd_advance(3)

    rts

 cmd_set_7_lines:
    copy_byte(6)
 cmd_set_6_lines:
    copy_byte(5)
 cmd_set_5_lines:
    copy_byte(4)
 cmd_set_4_lines:
    copy_byte(3)
 cmd_set_3_lines:
    copy_byte(2)
 cmd_set_2_lines:
    copy_byte(1)
 cmd_set_1_line:
    copy_byte(0)

    cmd_advance_lines()
}

byte cmd_set_lines_jmptab_0[9] = {
    0,
    lo(cmd_set_1_line),
    lo(cmd_set_2_lines),
    lo(cmd_set_3_lines),
    lo(cmd_set_4_lines),
    lo(cmd_set_5_lines),
    lo(cmd_set_6_lines),
    lo(cmd_set_7_lines),
    lo(cmd_set_8_lines)
}
byte cmd_set_lines_jmptab_1[9] = {
    0,
    hi(cmd_set_1_line),
    hi(cmd_set_2_lines),
    hi(cmd_set_3_lines),
    hi(cmd_set_4_lines),
    hi(cmd_set_5_lines),
    hi(cmd_set_6_lines),
    hi(cmd_set_7_lines),
    hi(cmd_set_8_lines)
}

byte cmd_clr_lines_tab_0[8] = { lo(rt_clr_1_lines_cycles), lo(rt_clr_2_lines_cycles), lo(rt_clr_3_lines_cycles), lo(rt_clr_4_lines_cycles), lo(rt_clr_5_lines_cycles), lo(rt_clr_6_lines_cycles), lo(rt_clr_7_lines_cycles), lo(rt_clr_8_lines_cycles), }

byte cmd_clr_lines_tab_1[8] = { hi(rt_clr_1_lines_cycles), hi(rt_clr_2_lines_cycles), hi(rt_clr_3_lines_cycles), hi(rt_clr_4_lines_cycles), hi(rt_clr_5_lines_cycles), hi(rt_clr_6_lines_cycles), hi(rt_clr_7_lines_cycles), hi(rt_clr_8_lines_cycles), }

function cmd_clr_lines()
{
    ldy cmd_lines

    lda cmd_clr_lines_tab_0-1, Y
    ldx cmd_clr_lines_tab_1-1, Y

    add_command()

    store_line_address()

    cmd_advance(1)
}

byte cmd_and_lines_tab_0[39] = { lo(rt_and_1_lines_cycles), lo(rt_and_2_lines_cycles), lo(rt_and_3_lines_cycles), lo(rt_and_4_lines_cycles), lo(rt_and_5_lines_cycles), lo(rt_and_6_lines_cycles), lo(rt_and_7_lines_cycles), lo(rt_and_8_lines_0_cycles), lo(rt_and_8_lines_1_cycles), lo(rt_and_8_lines_2_cycles), lo(rt_and_8_lines_3_cycles), lo(rt_and_8_lines_4_cycles), lo(rt_and_8_lines_5_cycles), lo(rt_and_8_lines_6_cycles), lo(rt_and_8_lines_7_cycles), lo(rt_and_8_lines_8_cycles), lo(rt_and_8_lines_9_cycles), lo(rt_and_8_lines_10_cycles), lo(rt_and_8_lines_11_cycles), lo(rt_and_8_lines_12_cycles), lo(rt_and_8_lines_13_cycles), lo(rt_and_8_lines_14_cycles), lo(rt_and_8_lines_15_cycles), lo(rt_and_8_lines_16_cycles), lo(rt_and_8_lines_17_cycles), lo(rt_and_8_lines_18_cycles), lo(rt_and_8_lines_19_cycles), lo(rt_and_8_lines_20_cycles), lo(rt_and_8_lines_21_cycles), lo(rt_and_8_lines_22_cycles), lo(rt_and_8_lines_23_cycles), lo(rt_and_8_lines_24_cycles), lo(rt_and_8_lines_25_cycles), lo(rt_and_8_lines_26_cycles), lo(rt_and_8_lines_27_cycles), lo(rt_and_8_lines_28_cycles), lo(rt_and_8_lines_29_cycles), lo(rt_and_8_lines_30_cycles), lo(rt_and_8_lines_31_cycles), }

byte cmd_and_lines_tab_1[39] = { hi(rt_and_1_lines_cycles), hi(rt_and_2_lines_cycles), hi(rt_and_3_lines_cycles), hi(rt_and_4_lines_cycles), hi(rt_and_5_lines_cycles), hi(rt_and_6_lines_cycles), hi(rt_and_7_lines_cycles), hi(rt_and_8_lines_0_cycles), hi(rt_and_8_lines_1_cycles), hi(rt_and_8_lines_2_cycles), hi(rt_and_8_lines_3_cycles), hi(rt_and_8_lines_4_cycles), hi(rt_and_8_lines_5_cycles), hi(rt_and_8_lines_6_cycles), hi(rt_and_8_lines_7_cycles), hi(rt_and_8_lines_8_cycles), hi(rt_and_8_lines_9_cycles), hi(rt_and_8_lines_10_cycles), hi(rt_and_8_lines_11_cycles), hi(rt_and_8_lines_12_cycles), hi(rt_and_8_lines_13_cycles), hi(rt_and_8_lines_14_cycles), hi(rt_and_8_lines_15_cycles), hi(rt_and_8_lines_16_cycles), hi(rt_and_8_lines_17_cycles), hi(rt_and_8_lines_18_cycles), hi(rt_and_8_lines_19_cycles), hi(rt_and_8_lines_20_cycles), hi(rt_and_8_lines_21_cycles), hi(rt_and_8_lines_22_cycles), hi(rt_and_8_lines_23_cycles), hi(rt_and_8_lines_24_cycles), hi(rt_and_8_lines_25_cycles), hi(rt_and_8_lines_26_cycles), hi(rt_and_8_lines_27_cycles), hi(rt_and_8_lines_28_cycles), hi(rt_and_8_lines_29_cycles), hi(rt_and_8_lines_30_cycles), hi(rt_and_8_lines_31_cycles), }

function cmd_and_lines()
{
    ldy cmd_lines
    cpy #8
    if (equal)
    {
        lda cmd_addr+1
        clc
        adc #8
        tay
    }

    lda cmd_and_lines_tab_0-1, Y
    ldx cmd_and_lines_tab_1-1, Y

    add_command()

    ldy cmd_lines
    lda cmd_and_lines_jmptab_0, Y
    sta tmp_addr+0
    lda cmd_and_lines_jmptab_1, Y
    sta tmp_addr+1

    ldy cmd_start

    jmp [tmp_addr]

 cmd_and_8_lines:
    lda cmd_addr+0
    sta dlist_data_0, X

    copy_byte_of_8(0)
    copy_byte_of_8(1)
    copy_byte_of_8(2)
    copy_byte_of_8(3)
    copy_byte_of_8(4)
    copy_byte_of_8(5)
    copy_byte_of_8(6)
    copy_byte_of_8(7)

    cmd_advance(3)

    rts

 cmd_and_7_lines:
    copy_byte(6)
 cmd_and_6_lines:
    copy_byte(5)
 cmd_and_5_lines:
    copy_byte(4)
 cmd_and_4_lines:
    copy_byte(3)
 cmd_and_3_lines:
    copy_byte(2)
 cmd_and_2_lines:
    copy_byte(1)
 cmd_and_1_line:
    copy_byte(0)

    store_line_address()

    cmd_advance_lines()
}

byte cmd_and_lines_jmptab_0[9] = {
    0,
    lo(cmd_and_1_line),
    lo(cmd_and_2_lines),
    lo(cmd_and_3_lines),
    lo(cmd_and_4_lines),
    lo(cmd_and_5_lines),
    lo(cmd_and_6_lines),
    lo(cmd_and_7_lines),
    lo(cmd_and_8_lines)
}
byte cmd_and_lines_jmptab_1[9] = {
    0,
    hi(cmd_and_1_line),
    hi(cmd_and_2_lines),
    hi(cmd_and_3_lines),
    hi(cmd_and_4_lines),
    hi(cmd_and_5_lines),
    hi(cmd_and_6_lines),
    hi(cmd_and_7_lines),
    hi(cmd_and_8_lines)
}

byte cmd_ora_lines_tab_0[39] = { lo(rt_ora_1_lines_cycles), lo(rt_ora_2_lines_cycles), lo(rt_ora_3_lines_cycles), lo(rt_ora_4_lines_cycles), lo(rt_ora_5_lines_cycles), lo(rt_ora_6_lines_cycles), lo(rt_ora_7_lines_cycles), lo(rt_ora_8_lines_0_cycles), lo(rt_ora_8_lines_1_cycles), lo(rt_ora_8_lines_2_cycles), lo(rt_ora_8_lines_3_cycles), lo(rt_ora_8_lines_4_cycles), lo(rt_ora_8_lines_5_cycles), lo(rt_ora_8_lines_6_cycles), lo(rt_ora_8_lines_7_cycles), lo(rt_ora_8_lines_8_cycles), lo(rt_ora_8_lines_9_cycles), lo(rt_ora_8_lines_10_cycles), lo(rt_ora_8_lines_11_cycles), lo(rt_ora_8_lines_12_cycles), lo(rt_ora_8_lines_13_cycles), lo(rt_ora_8_lines_14_cycles), lo(rt_ora_8_lines_15_cycles), lo(rt_ora_8_lines_16_cycles), lo(rt_ora_8_lines_17_cycles), lo(rt_ora_8_lines_18_cycles), lo(rt_ora_8_lines_19_cycles), lo(rt_ora_8_lines_20_cycles), lo(rt_ora_8_lines_21_cycles), lo(rt_ora_8_lines_22_cycles), lo(rt_ora_8_lines_23_cycles), lo(rt_ora_8_lines_24_cycles), lo(rt_ora_8_lines_25_cycles), lo(rt_ora_8_lines_26_cycles), lo(rt_ora_8_lines_27_cycles), lo(rt_ora_8_lines_28_cycles), lo(rt_ora_8_lines_29_cycles), lo(rt_ora_8_lines_30_cycles), lo(rt_ora_8_lines_31_cycles), }

byte cmd_ora_lines_tab_1[39] = { hi(rt_ora_1_lines_cycles), hi(rt_ora_2_lines_cycles), hi(rt_ora_3_lines_cycles), hi(rt_ora_4_lines_cycles), hi(rt_ora_5_lines_cycles), hi(rt_ora_6_lines_cycles), hi(rt_ora_7_lines_cycles), hi(rt_ora_8_lines_0_cycles), hi(rt_ora_8_lines_1_cycles), hi(rt_ora_8_lines_2_cycles), hi(rt_ora_8_lines_3_cycles), hi(rt_ora_8_lines_4_cycles), hi(rt_ora_8_lines_5_cycles), hi(rt_ora_8_lines_6_cycles), hi(rt_ora_8_lines_7_cycles), hi(rt_ora_8_lines_8_cycles), hi(rt_ora_8_lines_9_cycles), hi(rt_ora_8_lines_10_cycles), hi(rt_ora_8_lines_11_cycles), hi(rt_ora_8_lines_12_cycles), hi(rt_ora_8_lines_13_cycles), hi(rt_ora_8_lines_14_cycles), hi(rt_ora_8_lines_15_cycles), hi(rt_ora_8_lines_16_cycles), hi(rt_ora_8_lines_17_cycles), hi(rt_ora_8_lines_18_cycles), hi(rt_ora_8_lines_19_cycles), hi(rt_ora_8_lines_20_cycles), hi(rt_ora_8_lines_21_cycles), hi(rt_ora_8_lines_22_cycles), hi(rt_ora_8_lines_23_cycles), hi(rt_ora_8_lines_24_cycles), hi(rt_ora_8_lines_25_cycles), hi(rt_ora_8_lines_26_cycles), hi(rt_ora_8_lines_27_cycles), hi(rt_ora_8_lines_28_cycles), hi(rt_ora_8_lines_29_cycles), hi(rt_ora_8_lines_30_cycles), hi(rt_ora_8_lines_31_cycles), }

function cmd_ora_lines()
{
    ldy cmd_lines
    cpy #8
    if (equal)
    {
        lda cmd_addr+1
        clc
        adc #8
        tay
    }

    lda cmd_ora_lines_tab_0-1, Y
    ldx cmd_ora_lines_tab_1-1, Y

    add_command()

    ldy cmd_lines
    lda cmd_ora_lines_jmptab_0, Y
    sta tmp_addr+0
    lda cmd_ora_lines_jmptab_1, Y
    sta tmp_addr+1

    ldy cmd_start

    jmp [tmp_addr]

 cmd_ora_8_lines:
    lda cmd_addr+0
    sta dlist_data_0, X

    copy_byte_of_8(0)
    copy_byte_of_8(1)
    copy_byte_of_8(2)
    copy_byte_of_8(3)
    copy_byte_of_8(4)
    copy_byte_of_8(5)
    copy_byte_of_8(6)
    copy_byte_of_8(7)

    cmd_advance(3)

    rts

 cmd_ora_7_lines:
    copy_byte(6)
 cmd_ora_6_lines:
    copy_byte(5)
 cmd_ora_5_lines:
    copy_byte(4)
 cmd_ora_4_lines:
    copy_byte(3)
 cmd_ora_3_lines:
    copy_byte(2)
 cmd_ora_2_lines:
    copy_byte(1)
 cmd_ora_1_line:
    copy_byte(0)

    store_line_address()

    cmd_advance_lines()
}

byte cmd_ora_lines_jmptab_0[9] = {
    0,
    lo(cmd_ora_1_line),
    lo(cmd_ora_2_lines),
    lo(cmd_ora_3_lines),
    lo(cmd_ora_4_lines),
    lo(cmd_ora_5_lines),
    lo(cmd_ora_6_lines),
    lo(cmd_ora_7_lines),
    lo(cmd_ora_8_lines)
}
byte cmd_ora_lines_jmptab_1[9] = {
    0,
    hi(cmd_ora_1_line),
    hi(cmd_ora_2_lines),
    hi(cmd_ora_3_lines),
    hi(cmd_ora_4_lines),
    hi(cmd_ora_5_lines),
    hi(cmd_ora_6_lines),
    hi(cmd_ora_7_lines),
    hi(cmd_ora_8_lines)
}

pointer cmd_copy_and_1_lines_tab[8] = {
    rt_copy_and_0_0_cycles,
    rt_copy_and_1_1_cycles,
    rt_copy_and_2_2_cycles,
    rt_copy_and_3_3_cycles,
    rt_copy_and_4_4_cycles,
    rt_copy_and_5_5_cycles,
    rt_copy_and_6_6_cycles,
    rt_copy_and_7_7_cycles,
}

pointer cmd_copy_and_2_lines_tab[7] = {
    rt_copy_and_0_1_cycles,
    rt_copy_and_1_2_cycles,
    rt_copy_and_2_3_cycles,
    rt_copy_and_3_4_cycles,
    rt_copy_and_4_5_cycles,
    rt_copy_and_5_6_cycles,
    rt_copy_and_6_7_cycles,
}

pointer cmd_copy_and_3_lines_tab[6] = {
    rt_copy_and_0_2_cycles,
    rt_copy_and_1_3_cycles,
    rt_copy_and_2_4_cycles,
    rt_copy_and_3_5_cycles,
    rt_copy_and_4_6_cycles,
    rt_copy_and_5_7_cycles,
}

pointer cmd_copy_and_4_lines_tab[5] = {
    rt_copy_and_0_3_cycles,
    rt_copy_and_1_4_cycles,
    rt_copy_and_2_5_cycles,
    rt_copy_and_3_6_cycles,
    rt_copy_and_4_7_cycles,
}

pointer cmd_copy_and_5_lines_tab[4] = {
    rt_copy_and_0_4_cycles,
    rt_copy_and_1_5_cycles,
    rt_copy_and_2_6_cycles,
    rt_copy_and_3_7_cycles,
}

pointer cmd_copy_and_6_lines_tab[3] = {
    rt_copy_and_0_5_cycles,
    rt_copy_and_1_6_cycles,
    rt_copy_and_2_7_cycles,
}

pointer cmd_copy_and_7_lines_tab[2] = {
    rt_copy_and_0_6_cycles,
    rt_copy_and_1_7_cycles,
}

byte cmd_copy_and_lines_tab0[39] = { lo(cmd_copy_and_1_lines_tab), lo(cmd_copy_and_2_lines_tab), lo(cmd_copy_and_3_lines_tab), lo(cmd_copy_and_4_lines_tab), lo(cmd_copy_and_5_lines_tab), lo(cmd_copy_and_6_lines_tab), lo(cmd_copy_and_7_lines_tab), lo(rt_copy_and_all_0_cycles), lo(rt_copy_and_all_1_cycles), lo(rt_copy_and_all_2_cycles), lo(rt_copy_and_all_3_cycles), lo(rt_copy_and_all_4_cycles), lo(rt_copy_and_all_5_cycles), lo(rt_copy_and_all_6_cycles), lo(rt_copy_and_all_7_cycles), lo(rt_copy_and_all_8_cycles), lo(rt_copy_and_all_9_cycles), lo(rt_copy_and_all_10_cycles), lo(rt_copy_and_all_11_cycles), lo(rt_copy_and_all_12_cycles), lo(rt_copy_and_all_13_cycles), lo(rt_copy_and_all_14_cycles), lo(rt_copy_and_all_15_cycles), lo(rt_copy_and_all_16_cycles), lo(rt_copy_and_all_17_cycles), lo(rt_copy_and_all_18_cycles), lo(rt_copy_and_all_19_cycles), lo(rt_copy_and_all_20_cycles), lo(rt_copy_and_all_21_cycles), lo(rt_copy_and_all_22_cycles), lo(rt_copy_and_all_23_cycles), lo(rt_copy_and_all_24_cycles), lo(rt_copy_and_all_25_cycles), lo(rt_copy_and_all_26_cycles), lo(rt_copy_and_all_27_cycles), lo(rt_copy_and_all_28_cycles), lo(rt_copy_and_all_29_cycles), lo(rt_copy_and_all_30_cycles), lo(rt_copy_and_all_31_cycles), }

byte cmd_copy_and_lines_tab1[39] = { hi(cmd_copy_and_1_lines_tab), hi(cmd_copy_and_2_lines_tab), hi(cmd_copy_and_3_lines_tab), hi(cmd_copy_and_4_lines_tab), hi(cmd_copy_and_5_lines_tab), hi(cmd_copy_and_6_lines_tab), hi(cmd_copy_and_7_lines_tab), hi(rt_copy_and_all_0_cycles), hi(rt_copy_and_all_1_cycles), hi(rt_copy_and_all_2_cycles), hi(rt_copy_and_all_3_cycles), hi(rt_copy_and_all_4_cycles), hi(rt_copy_and_all_5_cycles), hi(rt_copy_and_all_6_cycles), hi(rt_copy_and_all_7_cycles), hi(rt_copy_and_all_8_cycles), hi(rt_copy_and_all_9_cycles), hi(rt_copy_and_all_10_cycles), hi(rt_copy_and_all_11_cycles), hi(rt_copy_and_all_12_cycles), hi(rt_copy_and_all_13_cycles), hi(rt_copy_and_all_14_cycles), hi(rt_copy_and_all_15_cycles), hi(rt_copy_and_all_16_cycles), hi(rt_copy_and_all_17_cycles), hi(rt_copy_and_all_18_cycles), hi(rt_copy_and_all_19_cycles), hi(rt_copy_and_all_20_cycles), hi(rt_copy_and_all_21_cycles), hi(rt_copy_and_all_22_cycles), hi(rt_copy_and_all_23_cycles), hi(rt_copy_and_all_24_cycles), hi(rt_copy_and_all_25_cycles), hi(rt_copy_and_all_26_cycles), hi(rt_copy_and_all_27_cycles), hi(rt_copy_and_all_28_cycles), hi(rt_copy_and_all_29_cycles), hi(rt_copy_and_all_30_cycles), hi(rt_copy_and_all_31_cycles), }

function cmd_copy_and_all_lines()
{
    ldy cmd_lines

    cpy #8
    if (equal)
    {
        lda cmd_addr+1
        eor #$10
        tay
        lda cmd_copy_and_lines_tab0-1+8, Y
        ldx cmd_copy_and_lines_tab1-1+8, Y
    }
    else
    {
        lda cmd_copy_and_lines_tab0-1, Y
        sta tmp_addr+0
        lda cmd_copy_and_lines_tab1-1, Y
        sta tmp_addr+1

        lda cmd_start
        asl A
        tay
        iny
        lda [tmp_addr], Y
        tax

        dey
        lda [tmp_addr], Y
    }

    add_command()

    ldy cmd_lines
    lda cmd_copy_and_jmptab_0, Y
    sta tmp_addr+0
    lda cmd_copy_and_jmptab_1, Y
    sta tmp_addr+1

    ldy cmd_start

    jmp [tmp_addr]

 cmd_copy_and_8_lines:
    lda cmd_addr+0
    sta dlist_data_0, X

    copy_byte_of_8(0)
    copy_byte_of_8(1)
    copy_byte_of_8(2)
    copy_byte_of_8(3)
    copy_byte_of_8(4)
    copy_byte_of_8(5)
    copy_byte_of_8(6)
    copy_byte_of_8(7)

    cmd_advance(3)

    rts

 cmd_copy_and_7_lines:
    copy_byte(6)
 cmd_copy_and_6_lines:
    copy_byte(5)
 cmd_copy_and_5_lines:
    copy_byte(4)
 cmd_copy_and_4_lines:
    copy_byte(3)
 cmd_copy_and_3_lines:
    copy_byte(2)
 cmd_copy_and_2_lines:
    copy_byte(1)
 cmd_copy_and_1_line:
    copy_byte(0)

    store_address_flip()

    cmd_advance_lines()
}

byte cmd_copy_and_jmptab_0[9] = {
    0,
    lo(cmd_copy_and_1_line),
    lo(cmd_copy_and_2_lines),
    lo(cmd_copy_and_3_lines),
    lo(cmd_copy_and_4_lines),
    lo(cmd_copy_and_5_lines),
    lo(cmd_copy_and_6_lines),
    lo(cmd_copy_and_7_lines),
    lo(cmd_copy_and_8_lines)
}
byte cmd_copy_and_jmptab_1[9] = {
    0,
    hi(cmd_copy_and_1_line),
    hi(cmd_copy_and_2_lines),
    hi(cmd_copy_and_3_lines),
    hi(cmd_copy_and_4_lines),
    hi(cmd_copy_and_5_lines),
    hi(cmd_copy_and_6_lines),
    hi(cmd_copy_and_7_lines),
    hi(cmd_copy_and_8_lines)
}

//

pointer cmd_copy_ora_1_lines_tab[8] = {
    rt_copy_ora_0_0_cycles,
    rt_copy_ora_1_1_cycles,
    rt_copy_ora_2_2_cycles,
    rt_copy_ora_3_3_cycles,
    rt_copy_ora_4_4_cycles,
    rt_copy_ora_5_5_cycles,
    rt_copy_ora_6_6_cycles,
    rt_copy_ora_7_7_cycles,
}

pointer cmd_copy_ora_2_lines_tab[7] = {
    rt_copy_ora_0_1_cycles,
    rt_copy_ora_1_2_cycles,
    rt_copy_ora_2_3_cycles,
    rt_copy_ora_3_4_cycles,
    rt_copy_ora_4_5_cycles,
    rt_copy_ora_5_6_cycles,
    rt_copy_ora_6_7_cycles,
}

pointer cmd_copy_ora_3_lines_tab[6] = {
    rt_copy_ora_0_2_cycles,
    rt_copy_ora_1_3_cycles,
    rt_copy_ora_2_4_cycles,
    rt_copy_ora_3_5_cycles,
    rt_copy_ora_4_6_cycles,
    rt_copy_ora_5_7_cycles,
}

pointer cmd_copy_ora_4_lines_tab[5] = {
    rt_copy_ora_0_3_cycles,
    rt_copy_ora_1_4_cycles,
    rt_copy_ora_2_5_cycles,
    rt_copy_ora_3_6_cycles,
    rt_copy_ora_4_7_cycles,
}

pointer cmd_copy_ora_5_lines_tab[4] = {
    rt_copy_ora_0_4_cycles,
    rt_copy_ora_1_5_cycles,
    rt_copy_ora_2_6_cycles,
    rt_copy_ora_3_7_cycles,
}

pointer cmd_copy_ora_6_lines_tab[3] = {
    rt_copy_ora_0_5_cycles,
    rt_copy_ora_1_6_cycles,
    rt_copy_ora_2_7_cycles,
}

pointer cmd_copy_ora_7_lines_tab[2] = {
    rt_copy_ora_0_6_cycles,
    rt_copy_ora_1_7_cycles,
}

byte cmd_copy_ora_lines_tab0[39] = { lo(cmd_copy_ora_1_lines_tab), lo(cmd_copy_ora_2_lines_tab), lo(cmd_copy_ora_3_lines_tab), lo(cmd_copy_ora_4_lines_tab), lo(cmd_copy_ora_5_lines_tab), lo(cmd_copy_ora_6_lines_tab), lo(cmd_copy_ora_7_lines_tab), lo(rt_copy_ora_all_0_cycles), lo(rt_copy_ora_all_1_cycles), lo(rt_copy_ora_all_2_cycles), lo(rt_copy_ora_all_3_cycles), lo(rt_copy_ora_all_4_cycles), lo(rt_copy_ora_all_5_cycles), lo(rt_copy_ora_all_6_cycles), lo(rt_copy_ora_all_7_cycles), lo(rt_copy_ora_all_8_cycles), lo(rt_copy_ora_all_9_cycles), lo(rt_copy_ora_all_10_cycles), lo(rt_copy_ora_all_11_cycles), lo(rt_copy_ora_all_12_cycles), lo(rt_copy_ora_all_13_cycles), lo(rt_copy_ora_all_14_cycles), lo(rt_copy_ora_all_15_cycles), lo(rt_copy_ora_all_16_cycles), lo(rt_copy_ora_all_17_cycles), lo(rt_copy_ora_all_18_cycles), lo(rt_copy_ora_all_19_cycles), lo(rt_copy_ora_all_20_cycles), lo(rt_copy_ora_all_21_cycles), lo(rt_copy_ora_all_22_cycles), lo(rt_copy_ora_all_23_cycles), lo(rt_copy_ora_all_24_cycles), lo(rt_copy_ora_all_25_cycles), lo(rt_copy_ora_all_26_cycles), lo(rt_copy_ora_all_27_cycles), lo(rt_copy_ora_all_28_cycles), lo(rt_copy_ora_all_29_cycles), lo(rt_copy_ora_all_30_cycles), lo(rt_copy_ora_all_31_cycles), }

byte cmd_copy_ora_lines_tab1[39] = { hi(cmd_copy_ora_1_lines_tab), hi(cmd_copy_ora_2_lines_tab), hi(cmd_copy_ora_3_lines_tab), hi(cmd_copy_ora_4_lines_tab), hi(cmd_copy_ora_5_lines_tab), hi(cmd_copy_ora_6_lines_tab), hi(cmd_copy_ora_7_lines_tab), hi(rt_copy_ora_all_0_cycles), hi(rt_copy_ora_all_1_cycles), hi(rt_copy_ora_all_2_cycles), hi(rt_copy_ora_all_3_cycles), hi(rt_copy_ora_all_4_cycles), hi(rt_copy_ora_all_5_cycles), hi(rt_copy_ora_all_6_cycles), hi(rt_copy_ora_all_7_cycles), hi(rt_copy_ora_all_8_cycles), hi(rt_copy_ora_all_9_cycles), hi(rt_copy_ora_all_10_cycles), hi(rt_copy_ora_all_11_cycles), hi(rt_copy_ora_all_12_cycles), hi(rt_copy_ora_all_13_cycles), hi(rt_copy_ora_all_14_cycles), hi(rt_copy_ora_all_15_cycles), hi(rt_copy_ora_all_16_cycles), hi(rt_copy_ora_all_17_cycles), hi(rt_copy_ora_all_18_cycles), hi(rt_copy_ora_all_19_cycles), hi(rt_copy_ora_all_20_cycles), hi(rt_copy_ora_all_21_cycles), hi(rt_copy_ora_all_22_cycles), hi(rt_copy_ora_all_23_cycles), hi(rt_copy_ora_all_24_cycles), hi(rt_copy_ora_all_25_cycles), hi(rt_copy_ora_all_26_cycles), hi(rt_copy_ora_all_27_cycles), hi(rt_copy_ora_all_28_cycles), hi(rt_copy_ora_all_29_cycles), hi(rt_copy_ora_all_30_cycles), hi(rt_copy_ora_all_31_cycles), }

function cmd_copy_ora_all_lines()
{
    ldy cmd_lines

    cpy #8
    if (equal)
    {
        lda cmd_addr+1
        eor #$10
        tay
        lda cmd_copy_ora_lines_tab0-1+8, Y
        ldx cmd_copy_ora_lines_tab1-1+8, Y
    }
    else
    {
        lda cmd_copy_ora_lines_tab0-1, Y
        sta tmp_addr+0
        lda cmd_copy_ora_lines_tab1-1, Y
        sta tmp_addr+1

        lda cmd_start
        asl A
        tay
        iny
        lda [tmp_addr], Y
        tax

        dey
        lda [tmp_addr], Y
    }

    add_command()

    ldy cmd_lines
    lda cmd_copy_ora_jmptab_0, Y
    sta tmp_addr+0
    lda cmd_copy_ora_jmptab_1, Y
    sta tmp_addr+1

    ldy cmd_start

    jmp [tmp_addr]

 cmd_copy_ora_8_lines:
    lda cmd_addr+0
    sta dlist_data_0, X

    copy_byte_of_8(0)
    copy_byte_of_8(1)
    copy_byte_of_8(2)
    copy_byte_of_8(3)
    copy_byte_of_8(4)
    copy_byte_of_8(5)
    copy_byte_of_8(6)
    copy_byte_of_8(7)

    cmd_advance(3)

    rts

 cmd_copy_ora_7_lines:
    copy_byte(6)
 cmd_copy_ora_6_lines:
    copy_byte(5)
 cmd_copy_ora_5_lines:
    copy_byte(4)
 cmd_copy_ora_4_lines:
    copy_byte(3)
 cmd_copy_ora_3_lines:
    copy_byte(2)
 cmd_copy_ora_2_lines:
    copy_byte(1)
 cmd_copy_ora_1_line:
    copy_byte(0)

    store_address_flip()

    cmd_advance_lines()
}

byte cmd_copy_ora_jmptab_0[9] = {
    0,
    lo(cmd_copy_ora_1_line),
    lo(cmd_copy_ora_2_lines),
    lo(cmd_copy_ora_3_lines),
    lo(cmd_copy_ora_4_lines),
    lo(cmd_copy_ora_5_lines),
    lo(cmd_copy_ora_6_lines),
    lo(cmd_copy_ora_7_lines),
    lo(cmd_copy_ora_8_lines)
}
byte cmd_copy_ora_jmptab_1[9] = {
    0,
    hi(cmd_copy_ora_1_line),
    hi(cmd_copy_ora_2_lines),
    hi(cmd_copy_ora_3_lines),
    hi(cmd_copy_ora_4_lines),
    hi(cmd_copy_ora_5_lines),
    hi(cmd_copy_ora_6_lines),
    hi(cmd_copy_ora_7_lines),
    hi(cmd_copy_ora_8_lines)
}

pointer cmd_setclr_1_lines_tab[8] = {
    rt_setclr_0_0_cycles,
    rt_setclr_1_1_cycles,
    rt_setclr_2_2_cycles,
    rt_setclr_3_3_cycles,
    rt_setclr_4_4_cycles,
    rt_setclr_5_5_cycles,
    rt_setclr_6_6_cycles,
    rt_setclr_7_7_cycles,
}

pointer cmd_setclr_2_lines_tab[7] = {
    rt_setclr_0_1_cycles,
    rt_setclr_1_2_cycles,
    rt_setclr_2_3_cycles,
    rt_setclr_3_4_cycles,
    rt_setclr_4_5_cycles,
    rt_setclr_5_6_cycles,
    rt_setclr_6_7_cycles,
}

pointer cmd_setclr_3_lines_tab[6] = {
    rt_setclr_0_2_cycles,
    rt_setclr_1_3_cycles,
    rt_setclr_2_4_cycles,
    rt_setclr_3_5_cycles,
    rt_setclr_4_6_cycles,
    rt_setclr_5_7_cycles,
}

pointer cmd_setclr_4_lines_tab[5] = {
    rt_setclr_0_3_cycles,
    rt_setclr_1_4_cycles,
    rt_setclr_2_5_cycles,
    rt_setclr_3_6_cycles,
    rt_setclr_4_7_cycles,
}

pointer cmd_setclr_5_lines_tab[4] = {
    rt_setclr_0_4_cycles,
    rt_setclr_1_5_cycles,
    rt_setclr_2_6_cycles,
    rt_setclr_3_7_cycles,
}

pointer cmd_setclr_6_lines_tab[3] = {
    rt_setclr_0_5_cycles,
    rt_setclr_1_6_cycles,
    rt_setclr_2_7_cycles,
}

pointer cmd_setclr_7_lines_tab[2] = {
    rt_setclr_0_6_cycles,
    rt_setclr_1_7_cycles,
}

byte cmd_setclr_lines_tab0[39] = { lo(cmd_setclr_1_lines_tab), lo(cmd_setclr_2_lines_tab), lo(cmd_setclr_3_lines_tab), lo(cmd_setclr_4_lines_tab), lo(cmd_setclr_5_lines_tab), lo(cmd_setclr_6_lines_tab), lo(cmd_setclr_7_lines_tab) }

byte cmd_setclr_lines_tab1[39] = { hi(cmd_setclr_1_lines_tab), hi(cmd_setclr_2_lines_tab), hi(cmd_setclr_3_lines_tab), hi(cmd_setclr_4_lines_tab), hi(cmd_setclr_5_lines_tab), hi(cmd_setclr_6_lines_tab), hi(cmd_setclr_7_lines_tab), }

function noreturn cmd_set_all_lines()
{
    ldy cmd_lines

    cpy #8
    if (equal)
    {
        ldy cmd_addr+1
        lda cmd_set_lines_tab_0-1+8, Y
        ldx cmd_set_lines_tab_1-1+8, Y
    }
    else
    {
        lda cmd_setclr_lines_tab0-1, Y
        sta tmp_addr+0
        lda cmd_setclr_lines_tab1-1, Y
        sta tmp_addr+1

        lda cmd_start
        asl A
        tay
        iny
        lda [tmp_addr], Y
        tax

        dey
        lda [tmp_addr], Y
    }

    add_command()

    ldy cmd_lines
    lda cmd_set_lines_jmptab_0, Y
    sta tmp_addr+0
    lda cmd_set_lines_jmptab_1, Y
    sta tmp_addr+1

    ldy cmd_start

    store_address()

    jmp [tmp_addr]
}

function cmd_tile_cache_write()
{
    ldy cmd_addr+1
    lda cmd_set_lines_tab_0-1+8, Y
    ldx cmd_set_lines_tab_1-1+8, Y

    add_command()

    ldy cmd_cache_start

    lda cmd_addr+0
    sta dlist_data_0, X

    copy_cache_byte_of_8(tile_cache_0, 0)
    copy_cache_byte_of_8(tile_cache_1, 1)
    copy_cache_byte_of_8(tile_cache_2, 2)
    copy_cache_byte_of_8(tile_cache_3, 3)
    copy_cache_byte_of_8(tile_cache_4, 4)
    copy_cache_byte_of_8(tile_cache_5, 5)
    copy_cache_byte_of_8(tile_cache_6, 6)
    copy_cache_byte_of_8(tile_cache_7, 7)

    cmd_advance(3)
}


function cmd_tile_cache_write_lines()
{
    ldy cmd_lines
    cpy #8

    beq cmd_tile_cache_write

#tell.bankoffset
    lda cmd_set_lines_tab_0-1, Y
    ldx cmd_set_lines_tab_1-1, Y

    add_command()

    store_line_address()

    ldy cmd_start
    lda cmd_tile_cache_write_lines_jmptab_0, Y
    sta tmp_addr+0
    lda cmd_tile_cache_write_lines_jmptab_1, Y
    sta tmp_addr+1

    lda cmd_lines
    sta tmp_byte

    ldy cmd_cache_start

    jmp [tmp_addr]

 cmd_tcwl_0:
    copy_cache_byte(tile_cache_0, 0)
    dec tmp_byte
    beq cmd_tcwl_0_end

    copy_cache_byte(tile_cache_1, 1)
    dec tmp_byte
    beq cmd_tcwl_0_end

    copy_cache_byte(tile_cache_2, 2)
    dec tmp_byte
    beq cmd_tcwl_0_end

    copy_cache_byte(tile_cache_3, 3)
    dec tmp_byte
    beq cmd_tcwl_0_end

    copy_cache_byte(tile_cache_4, 4)
    dec tmp_byte
    beq cmd_tcwl_0_end

    copy_cache_byte(tile_cache_5, 5)
    dec tmp_byte
    beq cmd_tcwl_0_end

    copy_cache_byte(tile_cache_6, 6)

 cmd_tcwl_0_end:
    cmd_advance_lines()
    rts

 cmd_tcwl_1:
    copy_cache_byte(tile_cache_1, 0)
    dec tmp_byte
    beq cmd_tcwl_1_end

    copy_cache_byte(tile_cache_2, 1)
    dec tmp_byte
    beq cmd_tcwl_1_end

    copy_cache_byte(tile_cache_3, 2)
    dec tmp_byte
    beq cmd_tcwl_1_end

    copy_cache_byte(tile_cache_4, 3)
    dec tmp_byte
    beq cmd_tcwl_1_end

    copy_cache_byte(tile_cache_5, 4)
    dec tmp_byte
    beq cmd_tcwl_1_end

    copy_cache_byte(tile_cache_6, 5)
    dec tmp_byte
    beq cmd_tcwl_1_end

    copy_cache_byte(tile_cache_7, 6)

 cmd_tcwl_1_end:
    cmd_advance_lines()
    rts

 cmd_tcwl_2:
    copy_cache_byte(tile_cache_2, 0)
    dec tmp_byte
    beq cmd_tcwl_2_end

    copy_cache_byte(tile_cache_3, 1)
    dec tmp_byte
    beq cmd_tcwl_2_end

    copy_cache_byte(tile_cache_4, 2)
    dec tmp_byte
    beq cmd_tcwl_2_end

    copy_cache_byte(tile_cache_5, 3)
    dec tmp_byte
    beq cmd_tcwl_2_end

    copy_cache_byte(tile_cache_6, 4)
    dec tmp_byte
    beq cmd_tcwl_2_end

    copy_cache_byte(tile_cache_7, 5)

 cmd_tcwl_2_end:
    cmd_advance_lines()
    rts

 cmd_tcwl_3:
    copy_cache_byte(tile_cache_3, 0)
    dec tmp_byte
    beq cmd_tcwl_3_end

    copy_cache_byte(tile_cache_4, 1)
    dec tmp_byte
    beq cmd_tcwl_3_end

    copy_cache_byte(tile_cache_5, 2)
    dec tmp_byte
    beq cmd_tcwl_3_end

    copy_cache_byte(tile_cache_6, 3)
    dec tmp_byte
    beq cmd_tcwl_3_end

    copy_cache_byte(tile_cache_7, 4)

 cmd_tcwl_3_end:
    cmd_advance_lines()
    rts

 cmd_tcwl_4:
    copy_cache_byte(tile_cache_4, 0)
    dec tmp_byte
    beq cmd_tcwl_4_end

    copy_cache_byte(tile_cache_5, 1)
    dec tmp_byte
    beq cmd_tcwl_4_end

    copy_cache_byte(tile_cache_6, 2)
    dec tmp_byte
    beq cmd_tcwl_4_end

    copy_cache_byte(tile_cache_7, 3)

 cmd_tcwl_4_end:
    cmd_advance_lines()
    rts

 cmd_tcwl_5:
    copy_cache_byte(tile_cache_5, 0)
    dec tmp_byte
    beq cmd_tcwl_5_end

    copy_cache_byte(tile_cache_6, 1)
    dec tmp_byte
    beq cmd_tcwl_5_end

    copy_cache_byte(tile_cache_7, 2)

 cmd_tcwl_5_end:
    cmd_advance_lines()
    rts

 cmd_tcwl_6:
    copy_cache_byte(tile_cache_6, 0)
    dec tmp_byte
    beq cmd_tcwl_6_end

    copy_cache_byte(tile_cache_7, 1)

 cmd_tcwl_6_end:
    cmd_advance_lines()
    rts

 cmd_tcwl_7:
    copy_cache_byte(tile_cache_7, 0)
    cmd_advance(1)
}

byte cmd_tile_cache_write_lines_jmptab_0[8] = { lo(cmd_tcwl_0), lo(cmd_tcwl_1), lo(cmd_tcwl_2), lo(cmd_tcwl_3), lo(cmd_tcwl_4), lo(cmd_tcwl_5), lo(cmd_tcwl_6), lo(cmd_tcwl_7), }

byte cmd_tile_cache_write_lines_jmptab_1[8] = { hi(cmd_tcwl_0), hi(cmd_tcwl_1), hi(cmd_tcwl_2), hi(cmd_tcwl_3), hi(cmd_tcwl_4), hi(cmd_tcwl_5), hi(cmd_tcwl_6), hi(cmd_tcwl_7), }

function dlist_finish_frame()
{
    lda #lo(rt_finish_frame_cycles)
    ldx #hi(rt_finish_frame_cycles)

    add_command()
}

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
inline cu_set_addr_prep()
{
    cu_set_addr()

    // half-set address for later
    sta $2006

    // dummy read
    lda $2007
}

// 26 cycles
inline cu_set_addr_prep_flip()
{
    cu_set_addr()

    // half-set address for later
    eor #$10
    sta $2006

    // dummy read
    lda $2007
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

byte rt_finish_frame_cycles[1] = {18}
function rt_finish_frame()
{
    lda _ppu_ctl0
    eor #CR_BACKADDR1000
    sta _ppu_ctl0
    sta $2000
}
