#define MAX_NMI_CYCLES 2000

// 62 cycles
zp_writer_rom:
    stx PPU.ADDRESS //  4
    sty PPU.ADDRESS //  4
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

dlist_wrap_jmp_rom:
    jmp dlist_0

/******************************************************************************/

function init_sendchr()
{
    // load zp_writer
    ldx #(zp_writer_rom_end-zp_writer_rom)-1
    do {
        lda zp_writer_rom, X
        sta zp_writer, X
        dex
    } while (not minus)

    // load dlist_wrap_jmp
    ldx #3-1
    do {
        lda dlist_wrap_jmp_rom, X
        sta dlist_wrap_jmp, X
        dex
    } while (not minus)

    // load dlist_start_jmp trampoline
    lda #$4C    // jmp abs
    sta dlist_start_jmp

    // init current dlist status
    //assign_16i(dlist_next_byte, dlist_0+0x37C)
    assign_16i(dlist_next_byte, dlist_0)

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

    // init dlists queue
    lda #0
    sta dlist_read_idx
    sta dlist_write_idx
    sta dlist_count

    setup_new_dlist()
}

// blocks until space frees up,
// if cycles are full, creates new dlist or blocks if we're already at max
function check_for_space_and_cycles()
{
retry_loop:
    sec // extra byte for possible RTS
    lda cmd_size
    adc dlist_next_byte+0
    sta tmp_addr+0
    lda #0
    adc dlist_next_byte+1
    sta tmp_addr+1

    ldx dlist_read_idx
    lda dlist_next_byte+1
    cmp dlists+1, X
    if (equal) {
        lda dlist_next_byte+0
        cmp dlists+0, X
        beq out_of_space
    }
    bpl space_next_byte_greater

    // next byte less, check end for overlap
    lda tmp_addr+1
    cmp dlists+1, X
    if (equal) {
        lda tmp_addr+0
        cmp dlists+0, X
        //beq out_of_space
    }

    bpl out_of_space
    // if both start and end are less then read (or end is equal), no chance of
    // overlap or wraparound
    jmp enough_space

space_next_byte_greater:
    // check end for wraparound
    // this is conservative, assuming that the command ends with 1
    // byte instructions that won't use up the "last chance" buffer
    lda tmp_addr+1
    cmp #hi(DLIST_LAST_CMD_START)
    // high byte will never be greater
    if (equal)
    {
        lda tmp_addr+0
        cmp #lo(DLIST_LAST_CMD_START)
    }
    bmi enough_space    // no wrapping

    // wrapping, determine where we'd end at the beginning
    lda tmp_addr+0
    sec
    sbc #lo(DLIST_WORST_CASE_SIZE)
    // will be 8 bit result
    cmp dlists+0, X
    beq enough_space
    bmi enough_space

out_of_space:
    // if there are no dlists ready, the one we check against
    // here will be the one in progress....
    // in which case we're stuck, so we need to end this dlist even though we're
    // not at the NMI limit yet
    ldx dlist_count
    bne retry_loop
    
    // if this is the first command, we're actually completely empty, not full
    lda dlist_cycles_left+0
    cmp #lo(MAX_NMI_CYCLES)
    bne space_stuck
    lda dlist_cycles_left+1
    cmp #hi(MAX_NMI_CYCLES)
    beq enough_space

space_stuck:
    finalize_dlist()
    setup_new_dlist()
    jmp retry_loop

enough_space:

    lda dlist_cycles_left+0
    sec
    sbc cmd_cycles
    sta dlist_cycles_left+0

    lda dlist_cycles_left+1
    sbc #0
    sta dlist_cycles_left+1

    if (minus) {
        finalize_dlist()
        setup_new_dlist()
        jmp retry_loop
    }
}

function finalize_dlist()
{
    // finalize the current dlist
    lda #$60    // RTS
    ldy #0
    sta [dlist_next_byte], Y

    inc dlist_count

    lda #1
    advance_next_byte()
    //clc
    //lda #1
    //adc dlist_next_byte+0
    //sta dlist_next_byte+0
    //lda #0
    //adc dlist_next_byte+1
    //sta dlist_next_byte+1
}

// blocks if already at max
function setup_new_dlist()
{
    assign_16i(dlist_cycles_left, MAX_NMI_CYCLES)
    
    do {
        lda dlist_count
        cmp #MAX_DLISTS
    } while (equal)

    // put on the queue
    ldx dlist_write_idx
    assign_16_16_x(dlists, dlist_next_byte)
    txa
    clc
    adc #2
    and #MAX_DLISTS_MOD_MASK
    sta dlist_write_idx
}

// A = 1st byte
function add_inst_1()
{
    ldy #0
    sta [dlist_next_byte],Y

    lda #1
    advance_next_byte()
}

// A = 1st byte, X = 2nd byte
function add_inst_2()
{
    ldy #0
    sta [dlist_next_byte],Y
    iny
    txa
    sta [dlist_next_byte],Y

    lda #2
    advance_next_byte()
}

// A = 1st byte, X = 2nd byte, Y = 3rd byte
function add_inst_3()
{
    sty tmp_byte
    ldy #0
    sta [dlist_next_byte],Y
    iny
    txa
    sta [dlist_next_byte],Y
    iny
    lda tmp_byte
    sta [dlist_next_byte],Y

    lda #3
    advance_next_byte()
}

// number of bytes in A, will perform inc and wrap on dlist_next_byte
function advance_next_byte()
{
    clc
    adc dlist_next_byte+0
    sta dlist_next_byte+0
    lda #0
    adc dlist_next_byte+1
    sta dlist_next_byte+1

    cmp #hi(DLIST_LAST_CMD_START)
    bne no_dlist_wrap

    lda dlist_next_byte+0
    cmp #lo(DLIST_LAST_CMD_START)
    beq no_dlist_wrap
    bmi no_dlist_wrap

    tax
    lda #$EA    // NOP
    do {
        sta (DLIST_LAST_CMD_START&0xff00), X
        inx
        cpx #lo(dlist_wrap_jmp)
    } while (not equal)
    
    assign_16i(dlist_next_byte, dlist_0)

no_dlist_wrap:
}

function sendchr_finish_frame()
{
    ldx #9
    ldy #12
    stx cmd_size
    sty cmd_cycles

    check_for_space_and_cycles()
    lda #$A5        // lda zp:  3 cycles, 2 bytes
    ldx #_ppu_ctl0
    add_inst_2()

    lda #$49        // eor imm: 2 cycles, 2 bytes
    ldx #CR_BACKADDR1000
    add_inst_2()

    lda #$85        // sta zp:  3 cycles, 2 bytes
    ldx #_ppu_ctl0
    add_inst_2()

    lda #$8D        // sta abs: 4 cycles, 3 bytes
    ldx #$00
    ldy #$20
    add_inst_3()

    finalize_dlist()

    setup_new_dlist()
}

/******************************************************************************/

// VRAM access library

// Y = address low, X = address high, A = value to OR
// 34 cycles
function vram_byte_or_update()
{
    stx $2006   // 4
    sty $2006   // 4
    cmp $2007   // 4 ; flush VRAM read buffer
    ora $2007   // 4
    stx $2006   // 4
    sty $2006   // 4
    sta $2007   // 4
    // rts ; 6
}

// Y = address low, X = address high, A = value to OR
// 34 cycles
function vram_byte_and_update()
{
    stx $2006   // 4
    sty $2006   // 4
    cmp $2007   // 4 ; flush VRAM read buffer
    and $2007   // 4
    stx $2006   // 4
    sty $2006   // 4
    sta $2007   // 4
    // rts ; 6
}

// A = fill value, Y = address low, X = address high
// 46 cycles
function vram_fill_tile()
{
    stx $2006       // 4
    sty $2006       // 4

    sta $2007       // 4 (0)
    sta $2007       // 4 (1)
    sta $2007       // 4 (2)
    sta $2007       // 4 (3)
    sta $2007       // 4 (4)
    sta $2007       // 4 (5)
    sta $2007       // 4 (6)
    sta $2007       // 4 (7)
    // rts ; 6
}

// Y = address low, X = address high
// 139 cycles
function noreturn vram_copy_tile()
{
    stx $2006       // 4
    sty $2006       // 4
    lda $2007       // 4

    lda $2007       // 4 * 8
    sta zp_immed_0  // 3 * 8
    lda $2007
    sta zp_immed_1
    lda $2007
    sta zp_immed_2
    lda $2007
    sta zp_immed_3
    lda $2007
    sta zp_immed_4
    lda $2007
    sta zp_immed_5
    lda $2007
    sta zp_immed_6
    lda $2007
    sta zp_immed_7

    lda flip_nametable, X   // 4
    tax             // 2

    jmp zp_writer   // 3 + 62
}

/******************************************************************************/

// command generation

// cmd_addr = VRAM address
// cmd_byte = byte to OR
function cmd_or_one_byte()
{
    ldx #9
    ldy #46
    stx cmd_size
    sty cmd_cycles
    check_for_space_and_cycles()

    lda #$A0        // ldy imm: 2 cycles, 2 bytes
    ldx cmd_addr+0
    add_inst_2()

    lda #$A2        // ldx imm: 2 cycles, 2 bytes
    ldx cmd_addr+1
    add_inst_2()

    lda #$A9        // lda imm: 2 cycles, 2 bytes
    ldx cmd_byte
    add_inst_2()

    lda #$20        // jsr: 6 + 34 cycles, 3 bytes
    ldx #lo(vram_byte_or_update)
    ldy #hi(vram_byte_or_update)
    add_inst_3()
}

// cmd_addr = VRAM address
// cmd_byte = byte to OR
function cmd_and_one_byte()
{
    ldx #9
    ldy #46
    stx cmd_size
    sty cmd_cycles
    check_for_space_and_cycles()

    lda #$A0        // ldy imm: 2 cycles, 2 bytes
    ldx cmd_addr+0
    add_inst_2()

    lda #$A2        // ldx imm: 2 cycles, 2 bytes
    ldx cmd_addr+1
    add_inst_2()

    lda #$A9        // lda imm: 2 cycles, 2 bytes
    ldx cmd_byte
    add_inst_2()

    lda #$20        // jsr: 6 + 34 cycles, 3 bytes
    ldx #lo(vram_byte_and_update)
    ldy #hi(vram_byte_and_update)
    add_inst_3()
}

// cmd_addr = VRAM address
// cmd_byte = byte to set
function cmd_set_one_byte()
{
    ldx #15
    ldy #18
    stx cmd_size
    sty cmd_cycles
    check_for_space_and_cycles()

    lda #$A0        // ldy imm: 2 cycles, 2 bytes
    ldx cmd_addr+0
    add_inst_2()

    lda #$A2        // ldx imm: 2 cycles, 2 bytes
    ldx cmd_addr+1
    add_inst_2()

    lda #$A9        // lda imm: 2 cycles, 2 bytes
    ldx cmd_byte
    add_inst_2()

    lda #$8E        // stx abs: 4 cycles, 3 bytes
    ldx #$06
    ldy #$20
    add_inst_3()

    lda #$8C        // sty abs: 4 cycles, 3 bytes
    ldx #$06
    ldy #$20
    add_inst_3()

    lda #$8D        // sta abs: 4 cycles, 3 bytes
    ldx #$07
    ldy #$20
    add_inst_3()
}

inline cmd_or_2007_sta(src, dst)
{
    lda #$AD    // lda abs: 4 cycles, 3 bytes
    ldx #$07
    ldy #$20
    add_inst_3()

    lda #$09    // ora imm: 2 cycles, 2 bytes
    ldx (src)
    add_inst_2()

    lda #$85    // sta zp: 3 cycles, 2 bytes
    ldx #(dst)
    add_inst_2()
}

inline cmd_and_2007_sta(src, dst)
{
    lda #$AD    // lda abs: 4 cycles, 3 bytes
    ldx #$07
    ldy #$20
    add_inst_3()

    lda #$29    // and imm: 2 cycles, 2 bytes
    ldx (src)
    add_inst_2()

    lda #$85    // sta zp: 3 cycles, 2 bytes
    ldx #(dst)
    add_inst_2()
}

inline cmd_lda_sta(src, dst)
{
    lda #$A9    // lda imm: 2 cycles, 2 bytes
    ldx src
    add_inst_2()

    lda #$85    // sta zp: 3 cycles, 2 bytes
    ldx #(dst)
    add_inst_2()
}

// cmd_addr = VRAM address
// cmd_byte = 8 bytes to OR
function cmd_or_tile_copy()
{
    ldx #74
    ldy #158
    stx cmd_size
    sty cmd_cycles
    check_for_space_and_cycles()

    lda #$A0    // ldy imm: 2 cycles, 2 bytes
    ldx cmd_addr+0
    add_inst_2()

    lda #$A2    // ldx imm: 2 cycles, 2 bytes
    ldy cmd_addr+1
    ldx flip_nametable, Y
    add_inst_2()

    lda #$8E    // stx abs: 4 cycles, 3 bytes
    ldx #$06
    ldy #$20
    add_inst_3()

    lda #$8C    // sty abs: 4 cycles, 3 bytes
    ldx #$06
    ldy #$20
    add_inst_3()

    lda #$AD    // lda abs: 4 cycles, 3 bytes
    ldx #$07
    ldy #$20
    add_inst_3()

    cmd_or_2007_sta(cmd_byte+0,zp_immed_0)  // 9 cycles, 7 bytes * 8
    cmd_or_2007_sta(cmd_byte+1,zp_immed_1)
    cmd_or_2007_sta(cmd_byte+2,zp_immed_2)
    cmd_or_2007_sta(cmd_byte+3,zp_immed_3)
    cmd_or_2007_sta(cmd_byte+4,zp_immed_4)
    cmd_or_2007_sta(cmd_byte+5,zp_immed_5)
    cmd_or_2007_sta(cmd_byte+6,zp_immed_6)
    cmd_or_2007_sta(cmd_byte+7,zp_immed_7)

    lda #$A2    // ldx imm: 2 cycles, 2 bytes
    ldx cmd_addr+1
    add_inst_2()

    lda #$20    // jsr: 6 + 62 cycles, 3 bytes
    ldx #lo(zp_writer)
    ldy #hi(zp_writer)
    add_inst_3()
}

// cmd_addr = VRAM address
// cmd_byte = 8 bytes to OR
function cmd_or_tile_update()
{
    ldx #72
    ldy #156
    stx cmd_size
    sty cmd_cycles
    check_for_space_and_cycles()

    lda #$A0    // ldy imm: 2 cycles, 2 bytes
    ldx cmd_addr+0
    add_inst_2()

    lda #$A2    // ldx imm: 2 cycles, 2 bytes
    ldx cmd_addr+1
    add_inst_2()

    lda #$8E    // stx abs: 4 cycles, 3 bytes
    ldx #$06
    ldy #$20
    add_inst_3()

    lda #$8C    // sty abs: 4 cycles, 3 bytes
    ldx #$06
    ldy #$20
    add_inst_3()

    lda #$AD    // lda abs: 4 cycles, 3 bytes
    ldx #$07
    ldy #$20
    add_inst_3()

    cmd_or_2007_sta(cmd_byte+0,zp_immed_0)  // 9 cycles, 7 bytes * 8
    cmd_or_2007_sta(cmd_byte+1,zp_immed_1)
    cmd_or_2007_sta(cmd_byte+2,zp_immed_2)
    cmd_or_2007_sta(cmd_byte+3,zp_immed_3)
    cmd_or_2007_sta(cmd_byte+4,zp_immed_4)
    cmd_or_2007_sta(cmd_byte+5,zp_immed_5)
    cmd_or_2007_sta(cmd_byte+6,zp_immed_6)
    cmd_or_2007_sta(cmd_byte+7,zp_immed_7)

    lda #$20    // jsr: 6 + 62 cycles, 3 bytes
    ldx #lo(zp_writer)
    ldy #hi(zp_writer)
    add_inst_3()
}

// cmd_addr = VRAM address
// cmd_byte = 8 bytes to OR
function cmd_and_tile_copy()
{
    ldx #74
    ldy #158
    stx cmd_size
    sty cmd_cycles
    check_for_space_and_cycles()

    lda #$A0    // ldy imm: 2 cycles, 2 bytes
    ldx cmd_addr+0
    add_inst_2()

    lda #$A2    // ldx imm: 2 cycles, 2 bytes
    ldy cmd_addr+1
    ldx flip_nametable, Y
    add_inst_2()

    lda #$8E    // stx abs: 4 cycles, 3 bytes
    ldx #$06
    ldy #$20
    add_inst_3()

    lda #$8C    // sty abs: 4 cycles, 3 bytes
    ldx #$06
    ldy #$20
    add_inst_3()

    lda #$AD    // lda abs: 4 cycles, 3 bytes
    ldx #$07
    ldy #$20
    add_inst_3()

    cmd_and_2007_sta(cmd_byte+0,zp_immed_0)  // 9 cycles, 7 bytes * 8
    cmd_and_2007_sta(cmd_byte+1,zp_immed_1)
    cmd_and_2007_sta(cmd_byte+2,zp_immed_2)
    cmd_and_2007_sta(cmd_byte+3,zp_immed_3)
    cmd_and_2007_sta(cmd_byte+4,zp_immed_4)
    cmd_and_2007_sta(cmd_byte+5,zp_immed_5)
    cmd_and_2007_sta(cmd_byte+6,zp_immed_6)
    cmd_and_2007_sta(cmd_byte+7,zp_immed_7)

    lda #$A2    // ldx imm: 2 cycles, 2 bytes
    ldx cmd_addr+1
    add_inst_2()

    lda #$20    // jsr: 6 + 62 cycles, 3 bytes
    ldx #lo(zp_writer)
    ldy #hi(zp_writer)
    add_inst_3()
}

// cmd_addr = VRAM address
// cmd_byte = 8 bytes to OR
function cmd_and_tile_update()
{
    ldx #72
    ldy #156
    stx cmd_size
    sty cmd_cycles
    check_for_space_and_cycles()

    lda #$A0    // ldy imm: 2 cycles, 2 bytes
    ldx cmd_addr+0
    add_inst_2()

    lda #$A2    // ldx imm: 2 cycles, 2 bytes
    ldx cmd_addr+1
    add_inst_2()

    lda #$8E    // stx abs: 4 cycles, 3 bytes
    ldx #$06
    ldy #$20
    add_inst_3()

    lda #$8C    // sty abs: 4 cycles, 3 bytes
    ldx #$06
    ldy #$20
    add_inst_3()

    lda #$AD    // lda abs: 4 cycles, 3 bytes
    ldx #$07
    ldy #$20
    add_inst_3()

    cmd_and_2007_sta(cmd_byte+0,zp_immed_0)  // 9 cycles, 7 bytes * 8
    cmd_and_2007_sta(cmd_byte+1,zp_immed_1)
    cmd_and_2007_sta(cmd_byte+2,zp_immed_2)
    cmd_and_2007_sta(cmd_byte+3,zp_immed_3)
    cmd_and_2007_sta(cmd_byte+4,zp_immed_4)
    cmd_and_2007_sta(cmd_byte+5,zp_immed_5)
    cmd_and_2007_sta(cmd_byte+6,zp_immed_6)
    cmd_and_2007_sta(cmd_byte+7,zp_immed_7)

    lda #$20    // jsr: 6 + 62 cycles, 3 bytes
    ldx #lo(zp_writer)
    ldy #hi(zp_writer)
    add_inst_3()
}

// cmd_addr = VRAM address
// cmd_byte = 8 bytes to write
function cmd_tile_set()
{
    ldx #39
    ldy #112
    stx cmd_size
    sty cmd_cycles
    check_for_space_and_cycles()

    cmd_lda_sta(cmd_byte+0,zp_immed_0)   // 5 cycles, 4 bytes * 8
    cmd_lda_sta(cmd_byte+1,zp_immed_1)
    cmd_lda_sta(cmd_byte+2,zp_immed_2)
    cmd_lda_sta(cmd_byte+3,zp_immed_3)
    cmd_lda_sta(cmd_byte+4,zp_immed_4)
    cmd_lda_sta(cmd_byte+5,zp_immed_5)
    cmd_lda_sta(cmd_byte+6,zp_immed_6)
    cmd_lda_sta(cmd_byte+7,zp_immed_7)

    lda #$A0    // ldy imm: 2 cycles, 2 bytes
    ldx cmd_addr+0
    add_inst_2()

    lda #$A2    // ldx imm: 2 cycles, 2 bytes
    ldx cmd_addr+1
    add_inst_2()

    lda #$20    // jsr: 6 + 62 cycles, 3 bytes
    ldx #lo(zp_writer)
    ldy #hi(zp_writer)
    add_inst_3()
}

// cmd_addr = VRAM address
function cmd_tile_clear()
{
    ldx #5
    ldy #54
    stx cmd_size
    sty cmd_cycles
    check_for_space_and_cycles()

    
    lda #$A9    // lda imm: 2 cycles, 2 bytes
    ldx #0
    add_inst_2()

    lda #$20    // jsr: 6 + 46 cycles, 3 bytes
    ldx #lo(vram_fill_tile)
    ldy #hi(vram_fill_tile)
    add_inst_3()
}

// cmd_addr = VRAM address
function cmd_tile_copy()
{
    ldx #7
    ldy #149
    stx cmd_size
    sty cmd_cycles
    check_for_space_and_cycles()

    lda #$A0    // ldy imm: 2 cycles, 2 bytes
    ldx cmd_addr+0
    add_inst_2()

    lda #$A2    // ldx imm: 2 cycles, 2 bytes
    ldy cmd_addr+1
    ldx flip_nametable, Y
    add_inst_2()

    lda #$20    // jsr: 6 + 139 cycles, 3 bytes
    ldx #lo(vram_copy_tile)
    ldy #hi(vram_copy_tile)
    add_inst_3()
}
