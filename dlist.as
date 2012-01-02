// display list stuff

#define MAX_VBLANK_CYCLES 2000

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

rangetab:
#incbin "rangetab.bin"

inline zp_writer_X_lines(lines) {
    stx PPU.ADDRESS //  4
    sty PPU.ADDRESS //  4
    jmp zp_writer+6+(5*(8-lines))   // 3
}

function noreturn zp_writer_1_line() { zp_writer_X_lines(1) }
function noreturn zp_writer_2_lines() { zp_writer_X_lines(2) }
function noreturn zp_writer_3_lines() { zp_writer_X_lines(3) }
function noreturn zp_writer_4_lines() { zp_writer_X_lines(4) }
function noreturn zp_writer_5_lines() { zp_writer_X_lines(5) }
function noreturn zp_writer_6_lines() { zp_writer_X_lines(6) }
function noreturn zp_writer_7_lines() { zp_writer_X_lines(7) }

pointer zp_writer_lines_tab[8] = {
    zp_writer_1_line,   // 23 (11 + 6 * lines + 6)
    zp_writer_2_lines,  // 29
    zp_writer_3_lines,  // 35
    zp_writer_4_lines,  // 41
    zp_writer_5_lines,  // 47
    zp_writer_6_lines,  // 53
    zp_writer_7_lines,  // 59
    zp_writer,          // 62 (straight up)
}

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
    assign_16i(dlist_next_byte, dlist_0)
    assign(dlist_interrupted, #0)
    assign_16i(dlist_cycles_left, MAX_VBLANK_CYCLES)

    lda #$0 // BRK
    sta dlist_0

    assign_16i(dlist_start, dlist_0)

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

inline check_for_interruption()
{
    lsr dlist_interrupted
    if (carry)
    {
        handle_interruption()
    }
}

inline wait_for_interruption()
{
    do {
        lsr dlist_interrupted
    } while (not carry)
    handle_interruption()
}

function handle_interruption()
{
    assign_16i(dlist_cycles_left, MAX_VBLANK_CYCLES)
    assign_16_16(dlist_start, dlist_end)
}

// blocks until space frees up,
// if cycles are full, creates new dlist or blocks if we're already at max
function check_for_space_and_cycles()
{
    check_for_interruption()

    sec // extra byte for BRK
    lda cmd_size
    adc dlist_next_byte+0
    sta tmp_addr+0
    lda #0
    adc dlist_next_byte+1
    sta tmp_addr+1

    lda dlist_next_byte+1
    cmp dlist_start+1
    if (equal) {
        lda dlist_next_byte+0
        cmp dlist_start+0
        beq out_of_space
    }
    bpl space_next_byte_greater

    // next byte less, check end for overlap
    lda tmp_addr+1
    cmp dlist_start+1
    if (equal) {
        lda tmp_addr+0
        cmp dlist_start+0
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
    cmp dlist_start+0
    beq enough_space
    bmi enough_space

out_of_space:
    
    // if this is the first command, we're actually completely empty, not full
    lda dlist_cycles_left+0
    cmp #lo(MAX_VBLANK_CYCLES)
    bne space_stuck
    lda dlist_cycles_left+1
    cmp #hi(MAX_VBLANK_CYCLES)
    beq enough_space

space_stuck:
    inc_16(stuck_cnt)
    
    wait_for_interruption()

enough_space:

    assign_16_16(dlist_first_inst_addr, dlist_next_byte)

cycles_wait:
    lda dlist_cycles_left+0
    sec
    sbc cmd_cycles
    sta dlist_cycles_left+0

    lda dlist_cycles_left+1
    sbc #0
    sta dlist_cycles_left+1

    if (minus) {
        wait_for_interruption()
        jmp cycles_wait 
    }
}

// A is first byte of the command
inline finalize_command(cmd_byte)
{
    lda #$0     // BRK
    tax
    sta [dlist_next_byte,X]

    // replace the initial BRK
    lda #cmd_byte
    sta [dlist_first_inst_addr,X]

    // no advance, we will be overwriting that BRK later
}

/******************************************************************************/

// A = 1st byte
inline add_inst_1()
{
    ldy #0
    sta [dlist_next_byte],Y

    lda #1
    advance_next_byte()
}

// A = 1st byte, X = 2nd byte
inline add_inst_2()
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
inline add_inst_3()
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

inline add_inst_1_first()
{
    lda #1
    advance_next_byte()
}

// A = 2nd byte
inline add_inst_2_first()
{
    ldy #1
    sta [dlist_next_byte],Y

    lda #2
    advance_next_byte()
}

// A = 2nd byte, X = 3rd byte
inline add_inst_3_first()
{
    ldy #1
    sta [dlist_next_byte],Y
    iny
    txa
    sta [dlist_next_byte],Y

    lda #3
    advance_next_byte()
}

// number of bytes in A, will perform inc and wrap on dlist_next_byte
inline advance_next_byte()
{
    clc
    adc dlist_next_byte+0
    sta dlist_next_byte+0
    lda #0
    adc dlist_next_byte+1
    sta dlist_next_byte+1

    cmp #hi(DLIST_LAST_CMD_START)
    if (equal)
    {
        advance_low_check()
    }
}

function advance_low_check()
{
    lda dlist_next_byte+0
    cmp #lo(DLIST_LAST_CMD_START)
    if (not carry)
    {
        rts
    }

    tax
    lda #$EA    // NOP
    do {
        sta (DLIST_LAST_CMD_START&0xff00), X
        inx
        cpx #lo(dlist_wrap_jmp)
    } while (not equal)
    
    assign_16i(dlist_next_byte, dlist_0)
}

function sendchr_finish_frame()
{
    ldx #9
    ldy #12
    stx cmd_size
    sty cmd_cycles

    check_for_space_and_cycles()

    //lda #$A5        // lda zp:  3 cycles, 2 bytes
    lda #_ppu_ctl0
    add_inst_2_first()

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

    finalize_command($A5)

    assign_16i(dlist_cycles_left, 0)
}

/******************************************************************************/

// dlist processing during vblank
function process_dlist()
{
    // don't do anything if the main thread hasn't ack'd yet
    lda dlist_interrupted
    bne no_dlists

    // let the main thread know we were run
    lda #$1
    sta dlist_interrupted

    jmp dlist_start_jmp

no_dlists:
    inc wasted_vblanks
}

// from IRQ, when the end be reached
inline process_dlist_complete()
{
    // get rid of saved flags
    pla 

    // make sure we don't execute this one again even in the worst case
    lda #0  // BRK
    tax
    sta [dlist_start,X]

    // now done with dlist, get the address of the BRK, where the next
    // instruction will appear
    pla
    sec
    sbc #2
    sta dlist_end+0
    pla
    sbc #0
    sta dlist_end+1
}

/******************************************************************************/

// VRAM access library

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

// 16 + 7 * lines
byte cmd_X_update_lines_bytes[8] = {
    16 + (7 * 1),
    16 + (7 * 2),
    16 + (7 * 3),
    16 + (7 * 4),
    16 + (7 * 5),
    16 + (7 * 6),
    16 + (7 * 7),
    16 + (7 * 8),
}

// 22 + 9 * lines + zp_writer
byte cmd_X_update_lines_cycles[8] = {
    22 + (9 * 1) + (11 + (6 * 1) + 6),
    22 + (9 * 2) + (11 + (6 * 2) + 6),
    22 + (9 * 3) + (11 + (6 * 3) + 6),
    22 + (9 * 4) + (11 + (6 * 4) + 6),
    22 + (9 * 5) + (11 + (6 * 5) + 6),
    22 + (9 * 6) + (11 + (6 * 6) + 6),
    22 + (9 * 7) + (11 + (6 * 7) + 6),
    22 + (9 * 8) + 62
}

function cmd_X_update_lines()
{
    //
    lda cmd_lines
    tax
    lda cmd_X_update_lines_bytes-1, X
    sta cmd_size
    lda cmd_X_update_lines_cycles-1, X
    sta cmd_cycles

    check_for_space_and_cycles()

    lda cmd_addr+0
    ora cmd_start
    //tax
    //lda #$A0        // ldy imm: 2 cycles, 2 bytes
    add_inst_2_first()

    lda #$A2        // ldx imm: 2 cycles, 2 bytes
    ldx cmd_addr+1
    add_inst_2()

    lda #$8E        // stx abs: 4 cycles, 3 bytes
    ldx #$06
    ldy #$20
    add_inst_3()

    lda #$8C        // sty abs: 4 cycles, 3 bytes
    ldx #$06
    ldy #$20
    add_inst_3()

    // dummy read
    lda #$AD        // lda abs: 4 cycles, 3 bytes
    ldx #$07
    ldy #$20
    add_inst_3()

    // jump table via rts
    lda cmd_lines
    asl A
    tax
    lda cmd_X_update_lines_jmp_tab_1, X
    pha
    lda cmd_X_update_lines_jmp_tab_0, X
    pha
    rts

cmd_X_update_lines_8:
    cmd_X_2007_sta(zp_immed_0)  // 9 cycles, 7 bytes * lines
cmd_X_update_lines_7:
    cmd_X_2007_sta(zp_immed_1)
cmd_X_update_lines_6:
    cmd_X_2007_sta(zp_immed_2)
cmd_X_update_lines_5:
    cmd_X_2007_sta(zp_immed_3)
cmd_X_update_lines_4:
    cmd_X_2007_sta(zp_immed_4)
cmd_X_update_lines_3:
    cmd_X_2007_sta(zp_immed_5)
cmd_X_update_lines_2:
    cmd_X_2007_sta(zp_immed_6)
cmd_X_update_lines_1:    
    cmd_X_2007_sta(zp_immed_7)

    lda cmd_lines
    asl A
    tay
    lda zp_writer_lines_tab+0-2, Y
    tax
    lda zp_writer_lines_tab+1-2, Y
    tay
    lda #$20        // jsr: 6 + ?? cycles, 3 bytes
    add_inst_3()

    finalize_command($A0)
}

byte cmd_X_update_lines_jmp_tab_0, cmd_X_update_lines_jmp_tab_1
pointer cmd_X_update_lines_jmp_tab[8] = {
    cmd_X_update_lines_1-1,
    cmd_X_update_lines_2-1,
    cmd_X_update_lines_3-1,
    cmd_X_update_lines_4-1,
    cmd_X_update_lines_5-1,
    cmd_X_update_lines_6-1,
    cmd_X_update_lines_7-1,
    cmd_X_update_lines_8-1
}

// 10 + 5 * lines
byte cmd_set_lines_bytes[8] = {
    10 + (5 * 1),
    10 + (5 * 2),
    10 + (5 * 3),
    10 + (5 * 4),
    10 + (5 * 5),
    10 + (5 * 6),
    10 + (5 * 7),
    10 + (5 * 8),
}

// 12 + 6 * lines
byte cmd_set_lines_cycles[8] = {
    12 + (6 * 1),
    12 + (6 * 2),
    12 + (6 * 3),
    12 + (6 * 4),
    12 + (6 * 5),
    12 + (6 * 6),
    12 + (6 * 7),
    12 + (6 * 8),
}

function cmd_set_lines()
{
    //
    lda cmd_lines
    tax
    lda cmd_set_lines_bytes-1, X
    sta cmd_size
    lda cmd_set_lines_cycles-1, X
    sta cmd_cycles

    check_for_space_and_cycles()

    lda cmd_addr+0
    ora cmd_start
    //tax
    //lda #$A0        // ldy imm: 2 cycles, 2 bytes
    add_inst_2_first()

    lda #$A2        // ldx imm: 2 cycles, 2 bytes
    ldx cmd_addr+1
    add_inst_2()

    lda #$8E        // stx abs: 4 cycles, 3 bytes
    ldx #$06
    ldy #$20
    add_inst_3()

    lda #$8C        // sty abs: 4 cycles, 3 bytes
    ldx #$06
    ldy #$20
    add_inst_3()

    do {
        cmd_imm_sta_2007()    // 6 cycles, 5 bytes * lines
        dec cmd_lines
    } while (not zero)

    finalize_command($A0)
}

// 12 + 3 * lines
byte cmd_clr_lines_bytes[8] = {
    12 + (3 * 1),
    12 + (3 * 2),
    12 + (3 * 3),
    12 + (3 * 4),
    12 + (3 * 5),
    12 + (3 * 6),
    12 + (3 * 7),
    12 + (3 * 8),
}

// 14 + 4 * lines
byte cmd_clr_lines_cycles[8] = {
    14 + (4 * 1),
    14 + (4 * 2),
    14 + (4 * 3),
    14 + (4 * 4),
    14 + (4 * 5),
    14 + (4 * 6),
    14 + (4 * 7),
    14 + (4 * 8),
}

function cmd_clr_lines()
{
    //
    lda cmd_lines
    tax
    lda cmd_clr_lines_bytes-1, X
    sta cmd_size
    lda cmd_clr_lines_cycles-1, X
    sta cmd_cycles

    check_for_space_and_cycles()

    lda cmd_addr+0
    ora cmd_start
    //tax
    //lda #$A0        // ldy imm: 2 cycles, 2 bytes
    add_inst_2_first()

    lda #$A2        // ldx imm: 2 cycles, 2 bytes
    ldx cmd_addr+1
    add_inst_2()

    lda #$8E        // stx abs: 4 cycles, 3 bytes
    ldx #$06
    ldy #$20
    add_inst_3()

    lda #$8C        // sty abs: 4 cycles, 3 bytes
    ldx #$06
    ldy #$20
    add_inst_3()

    lda #$A9        // lda imm: 2 cycles, 2 bytes
    ldx #0
    add_inst_2()

    do {
        cmd_sta_2007()    // 4 cycles, 3 bytes * lines
        dec cmd_lines
    } while (not zero)

    finalize_command($A0)
}

// 18 + 7 * lines + 5 * (8-lines)
byte cmd_X_copy_all_lines_bytes[8] = {
    18 + (7 * 1) + (5 * (8 - 1)),
    18 + (7 * 2) + (5 * (8 - 2)),
    18 + (7 * 3) + (5 * (8 - 3)),
    18 + (7 * 4) + (5 * (8 - 4)),
    18 + (7 * 5) + (5 * (8 - 5)),
    18 + (7 * 6) + (5 * (8 - 6)),
    18 + (7 * 7) + (5 * (8 - 7)),
    18 + (7 * 8) + (5 * (8 - 8)),
}

// 86 + 9 * lines + 7 * (8-lines)
byte cmd_X_copy_all_lines_cycles[8] = {
    86 + (9 * 1) + (7 * (8 - 1)),
    86 + (9 * 2) + (7 * (8 - 2)),
    86 + (9 * 3) + (7 * (8 - 3)),
    86 + (9 * 4) + (7 * (8 - 4)),
    86 + (9 * 5) + (7 * (8 - 5)),
    86 + (9 * 6) + (7 * (8 - 6)),
    86 + (9 * 7) + (7 * (8 - 7)),
    86 + (9 * 8) + (7 * (8 - 8)),
}

function cmd_X_copy_all_lines()
{
    //
    lda cmd_lines
    tax
    lda cmd_X_copy_all_lines_bytes-1, X
    sta cmd_size
    lda cmd_X_copy_all_lines_cycles-1, X
    sta cmd_cycles

    check_for_space_and_cycles()

    //lda #$A0        // ldy imm: 2 cycles, 2 bytes
    lda cmd_addr+0
    add_inst_2_first()

    lda #$A2        // ldx imm: 2 cycles, 2 bytes
    ldy cmd_addr+1
    ldx flip_nametable, Y
    add_inst_2()

    lda #$8E        // stx abs: 4 cycles, 3 bytes
    ldx #$06
    ldy #$20
    add_inst_3()

    lda #$8C        // sty abs: 4 cycles, 3 bytes
    ldx #$06
    ldy #$20
    add_inst_3()

    // dummy read
    lda #$AD        // lda abs: 4 cycles, 3 bytes
    ldx #$07
    ldy #$20
    add_inst_3()

    lda cmd_lines
    asl A
    asl A
    asl A
    ora cmd_start
    tax
    lda rangetab-8, X
    sta cmd_cycles

    cmd_maybe_X_2007_sta(cmd_byte+0, zp_immed_0) // 9 cycles, 7 bytes * lines +
    cmd_maybe_X_2007_sta(cmd_byte+1, zp_immed_1) // 7 cycles, 5 bytes * (8 - lines)
    cmd_maybe_X_2007_sta(cmd_byte+2, zp_immed_2)
    cmd_maybe_X_2007_sta(cmd_byte+3, zp_immed_3)
    cmd_maybe_X_2007_sta(cmd_byte+4, zp_immed_4)
    cmd_maybe_X_2007_sta(cmd_byte+5, zp_immed_5)
    cmd_maybe_X_2007_sta(cmd_byte+6, zp_immed_6)
    cmd_maybe_X_2007_sta(cmd_byte+7, zp_immed_7)

    lda #$A2        // ldx imm: 2 cycles, 2 bytes
    ldx cmd_addr+1
    add_inst_2()

    lda #$20        // jsr: 6 + 62 cycles, 3 bytes
    ldx #lo(zp_writer)
    ldy #hi(zp_writer)
    add_inst_3()

    finalize_command($A0)
}

// 12 + 5 * lines + 3 * (8-lines)
byte cmd_set_all_lines_bytes[8] = {
    12 + (5 * 1) + (3 * (8 - 1)),
    12 + (5 * 2) + (3 * (8 - 2)),
    12 + (5 * 3) + (3 * (8 - 3)),
    12 + (5 * 4) + (3 * (8 - 4)),
    12 + (5 * 5) + (3 * (8 - 5)),
    12 + (5 * 6) + (3 * (8 - 6)),
    12 + (5 * 7) + (3 * (8 - 7)),
    12 + (5 * 8) + (3 * (8 - 8))
}

// 14 + 6 * lines + 4 * (8-lines)
byte cmd_set_all_lines_cycles[8] = {
    14 + (6 * 1) + (4 * (8 - 1)),
    14 + (6 * 2) + (4 * (8 - 2)),
    14 + (6 * 3) + (4 * (8 - 3)),
    14 + (6 * 4) + (4 * (8 - 4)),
    14 + (6 * 5) + (4 * (8 - 5)),
    14 + (6 * 6) + (4 * (8 - 6)),
    14 + (6 * 7) + (4 * (8 - 7)),
    14 + (6 * 8) + (4 * (8 - 8)),
}

function cmd_set_all_lines()
{
    //
    lda cmd_lines
    tax
    lda cmd_set_all_lines_bytes-1, X
    sta cmd_size
    lda cmd_set_all_lines_cycles-1, X
    sta cmd_cycles

    check_for_space_and_cycles()

    //lda #$A0        // ldy imm: 2 cycles, 2 bytes
    lda cmd_addr+0
    add_inst_2_first()

    lda #$A2        // ldx imm: 2 cycles, 2 bytes
    ldx cmd_addr+1
    add_inst_2()

    lda #$8E        // stx abs: 4 cycles, 3 bytes
    ldx #$06
    ldy #$20
    add_inst_3()

    lda #$8C        // sty abs: 4 cycles, 3 bytes
    ldx #$06
    ldy #$20
    add_inst_3()

    lda #$A0        // ldy imm: 2 cycles, 2 bytes
    ldx #0
    add_inst_2()

    lda cmd_lines
    asl A
    asl A
    asl A
    ora cmd_start
    tax
    lda rangetab-8, X
    sta cmd_cycles

    cmd_2007_maybe_Y_lda_A_2007_sta(cmd_byte+0) // 6 cycles, 5 bytes * lines +
    cmd_2007_maybe_Y_lda_A_2007_sta(cmd_byte+1) // 4 cycles, 3 bytes * (8 - lines)
    cmd_2007_maybe_Y_lda_A_2007_sta(cmd_byte+2)
    cmd_2007_maybe_Y_lda_A_2007_sta(cmd_byte+3)
    cmd_2007_maybe_Y_lda_A_2007_sta(cmd_byte+4)
    cmd_2007_maybe_Y_lda_A_2007_sta(cmd_byte+5)
    cmd_2007_maybe_Y_lda_A_2007_sta(cmd_byte+6)
    cmd_2007_maybe_Y_lda_A_2007_sta(cmd_byte+7)

    finalize_command($A0)
}

inline cmd_X_2007_sta(dst)
{
    lda #$AD    // lda abs: 4 cycles, 3 bytes
    ldx #$07
    ldy #$20
    add_inst_3()

    ldx cmd_start
    lda cmd_byte, X
    inx
    stx cmd_start
    tax
    lda cmd_op  // ora or and imm: 2 cycles, 2 bytes
    add_inst_2()

    lda #$85    // sta zp: 3 cycles, 2 bytes
    ldx #(dst)
    add_inst_2()
}

inline cmd_maybe_X_2007_sta(src, dst)
{
    lda #$AD    // lda abs: 4 cycles, 3 bytes
    ldx #$07
    ldy #$20
    add_inst_3()

    lsr cmd_cycles // operation line range
    if (carry)
    {
        lda cmd_op  // ora or and imm: 2 cycles, 2 bytes
        ldx (src)
        add_inst_2()
    }

    lda #$85    // sta zp: 3 cycles, 2 bytes
    ldx #(dst)
    add_inst_2()
}

inline cmd_2007_maybe_Y_lda_A_2007_sta(src)
{
    lda #$8C    // sty abs: 4 cycles, 3 bytes

    lsr cmd_cycles  // operation line range
    if (carry)
    {
        lda #$A9    // lda imm: 2 cycles, 2 bytes
        ldx (src)
        add_inst_2()

        lda #$8D    // sta abs: 4 cycles, 3 bytes
    }

    ldx #$07
    ldy #$20
    add_inst_3()
}

inline cmd_imm_sta_2007()
{
    ldx cmd_start
    lda cmd_byte, X
    inx
    stx cmd_start
    tax
    lda #$A9    // lda imm: 2 cycles, 2 bytes
    add_inst_2()

    lda #$8D    // sta abs: 4 cycles, 3 bytes
    ldx #$07
    ldy #$20
    add_inst_3()
}

inline cmd_sta_2007()
{
    lda #$8D    // sta abs: 4 cycles, 3 bytes
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

    lda (src)
    eor #$FF
    tax
    lda #$29    // and imm: 2 cycles, 2 bytes
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
function cmd_tile_clear()
{
    ldx #9
    ldy #58
    stx cmd_size
    sty cmd_cycles
    check_for_space_and_cycles()

    
    //lda #$A9    // lda imm: 2 cycles, 2 bytes
    lda #0
    add_inst_2_first()

    lda cmd_addr+0
    and #~7
    tax
    lda #$A0    // ldy imm: 2 cycles, 2 bytes
    add_inst_2()

    lda #$A2    // ldx imm: 2 cycles, 2 bytes
    ldx cmd_addr+1
    add_inst_2()

    lda #$20    // jsr: 6 + 46 cycles, 3 bytes
    ldx #lo(vram_fill_tile)
    ldy #hi(vram_fill_tile)
    add_inst_3()

    finalize_command($A9)
}

// cmd_addr = VRAM address
function cmd_tile_copy()
{
    ldx #7
    ldy #149
    stx cmd_size
    sty cmd_cycles
    check_for_space_and_cycles()

    //lda #$A0    // ldy imm: 2 cycles, 2 bytes
    lda cmd_addr+0
    add_inst_2_first()

    lda #$A2    // ldx imm: 2 cycles, 2 bytes
    ldy cmd_addr+1
    ldx flip_nametable, Y
    add_inst_2()

    lda #$20    // jsr: 6 + 139 cycles, 3 bytes
    ldx #lo(vram_copy_tile)
    ldy #hi(vram_copy_tile)
    add_inst_3()

    finalize_command($A0)
}
