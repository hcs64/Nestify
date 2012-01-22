// display list stuff

#define MAX_VBLANK_CYCLES 2120

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

byte zp_writer_lines_tab_0[8] = {
    lo(zp_writer_1_line),   // 23 (11 + 6 * lines + 6)
    lo(zp_writer_2_lines),  // 29
    lo(zp_writer_3_lines),  // 35
    lo(zp_writer_4_lines),  // 41
    lo(zp_writer_5_lines),  // 47
    lo(zp_writer_6_lines),  // 53
    lo(zp_writer_7_lines),  // 59
    lo(zp_writer),          // 62 (straight up)
}

byte zp_writer_lines_tab_1[8] = {
    hi(zp_writer_1_line),   // 23 (11 + 6 * lines + 6)
    hi(zp_writer_2_lines),  // 29
    hi(zp_writer_3_lines),  // 35
    hi(zp_writer_4_lines),  // 41
    hi(zp_writer_5_lines),  // 47
    hi(zp_writer_6_lines),  // 53
    hi(zp_writer_7_lines),  // 59
    hi(zp_writer),          // 62 (straight up)
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

    // load dlist_start_jmp trampoline
    lda #$4C    // jmp abs
    sta dlist_start_jmp

    // init current dlist status
    assign_16i(dlist_next_byte, dlist_0)
    assign_16i(dlist_cycles_left, MAX_VBLANK_CYCLES)
    assign(dlist_reset_cycles, #0)

    assign_16i(dlist_start, dlist_0)
    lda #0
    sta dlist_0

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

inline atomic_assign_16_16(dst, src)
{
    do {
        lda #0
        sta nmi_hit
        assign_16_16(dst, src)
        lda nmi_hit
    } while (not zero)
}

function wait_for_interruption()
{
    lda #0
    sta nmi_hit
    do {
        lda nmi_hit
    } while (zero)
}

inline check_reset_cycles()
{
    lsr dlist_reset_cycles
    if (carry)
    {
        // reset, subtract time of last command that was never exposed
        sec
        lda #lo(MAX_VBLANK_CYCLES)
        sbc last_cmd_cycles
        sta dlist_cycles_left+0
        lda #hi(MAX_VBLANK_CYCLES)
        sbc #0
        sta dlist_cycles_left+1
    }
}

function check_for_space_and_cycles()
{
    atomic_assign_16_16(dlist_write_limit, dlist_start)

    ldx cmd_size
    inx // 1 for BRK/CLC
    txa
    sec // 1 more for BRK
    adc dlist_next_byte+0
    sta tmp_addr+0
    lda #0
    adc dlist_next_byte+1
    sta tmp_addr+1

    lda dlist_next_byte+1
    cmp dlist_write_limit+1
    if (equal) {
        lda dlist_next_byte+0
        cmp dlist_write_limit+0
        beq exactly_at_dlist_start
    }
    bcs space_next_byte_greater

    // next byte less, check end for overlap
    lda tmp_addr+1
    cmp dlist_write_limit+1
    if (equal) {
        lda tmp_addr+0
        cmp dlist_write_limit+0
        beq out_of_space
    }
    bcs out_of_space

    // if both start and end are less than limit, no chance of
    // overlap or wraparound
    jmp enough_space

space_next_byte_greater:
    // check end for wraparound

    // this is conservative, assuming that the command ends with 1
    // byte instructions that won't use the "last chance" buffer
    lda tmp_addr+1
    cmp #hi(DLIST_LAST_CMD_START)
    // high byte will never be greater
    if (equal)
    {
        lda tmp_addr+0
        cmp #lo(DLIST_LAST_CMD_START)
    }
    bcc enough_space    // no wrapping

    // wrapping, insert wrap
    finalize_prev_command()

    add_inst_3_addr_first($4C, dlist_0)  // jmp abs

    assign_16i(dlist_next_byte, dlist_0)

    lda #lo(dlist_0)
    cmp dlist_write_limit+0
    bne space_for_wrap
    lda #hi(dlist_0)
    cmp dlist_write_limit+1
    bne space_for_wrap

    wait_for_interruption()

space_for_wrap:
    lda #0  // brk
    sta dlist_0

    jmp check_for_space_and_cycles

out_of_space:

    wait_for_interruption()

    lda dlist_reset_cycles
    if (not zero)
    {
        inc_16(stuck_cnt)
    }
    
    jmp check_for_space_and_cycles

exactly_at_dlist_start:
enough_space:

    check_reset_cycles()

    lda dlist_cycles_left+0
    sec
    sbc cmd_cycles
    sta dlist_cycles_left+0

    lda dlist_cycles_left+1
    sbc #0
    sta dlist_cycles_left+1

    if (minus)
    {
        // out of time for the next command, so previous must be final
        finalize_dlist()
    }
    else
    {
        // keep going incompletely
        finalize_prev_command()
    }
}

inline finalize_command()
{
    tya
    advance_next_byte()

    lda #$0     // BRK
    tay
    sta [dlist_next_byte], Y

    // no advance, we will be overwriting that BRK later
    lda cmd_cycles
    sta last_cmd_cycles
}

inline finalize_prev_command()
{
    // replace the initial BRK, exposing this command
    ldy #$0
    lda dlist_cmd_first_inst_byte
    sta [dlist_cmd_first_inst_addr], Y
}

function finalize_dlist()
{
    // NOTE: called before this command has been exposed, so this manipulation
    // is invisible to the NMI.
    // It will not skip over the initial BRK to get here, as we have not yet
    // inserted the CLC to indicate this is a complete command.
    //
    // There may be an issue if the NMI hits after the check_reset_cycles call,
    // that would run up to the start of this command. We would then have a
    // "complete" dlist that consists only of this command. The termination
    // will be such that it is handled correctly, but it will waste a frame
    // after doing only this one command. About 3 times in 5000 frames.

    // put a CLC over the old BRK
    ldy #0
    lda #$18    // CLC
    sta [dlist_next_byte], Y

    // put in another BRK
    lda #0      // BRK
    iny
    sta [dlist_next_byte], Y

    // moving on
    lda #2
    advance_next_byte()

    // and yet one more BRK to set up for the next command
    lda #0
    tay
    sta [dlist_next_byte], Y

    // replace the initial BRK, exposing this command
    lda dlist_cmd_first_inst_byte
    sta [dlist_cmd_first_inst_addr], Y

    // reset cycle count, less the new command that wouldn't fit
    sec
    lda #lo(MAX_VBLANK_CYCLES)
    sbc cmd_cycles
    sta dlist_cycles_left+0
    lda #hi(MAX_VBLANK_CYCLES)
    sbc #0
    sta dlist_cycles_left+1

    // Can't be needing to reset cycles, we haven't exposed anything from this
    // new dlist yet.
    lda #0
    sta dlist_reset_cycles
}

/******************************************************************************/

// A = 1st byte
inline add_inst_1()
{
    sta [dlist_next_byte],Y
    iny
}

// A = 1st byte
inline add_inst_2_immarg(arg)
{
    sta [dlist_next_byte],Y
    iny
    lda #arg
    sta [dlist_next_byte],Y
    iny
}

// A = 1st byte
inline add_inst_2_ldarg(arg)
{
    sta [dlist_next_byte],Y
    iny
    lda arg
    sta [dlist_next_byte],Y
    iny
}

// A = 1st byte, X = offset
inline add_inst_2_ldargX(arg)
{
    sta [dlist_next_byte],Y
    iny
    lda arg, X
    sta [dlist_next_byte],Y
    iny
}

inline add_inst_2_X(op,base)
{
    lda #op
    sta [dlist_next_byte],Y
    iny
    lda base, X
    sta [dlist_next_byte],Y
    iny
}

inline add_inst_3_A_addr(addr)
{
    sta [dlist_next_byte],Y
    iny

    lda #lo(addr)
    sta [dlist_next_byte],Y
    iny

    lda #hi(addr)
    sta [dlist_next_byte],Y
    iny
}

inline add_inst_3_addr(byte0,addr)
{
    lda #byte0
    sta [dlist_next_byte],Y
    iny

    lda #lo(addr)
    sta [dlist_next_byte],Y
    iny

    lda #hi(addr)
    sta [dlist_next_byte],Y
    iny
}

inline add_inst_3_lookup(byte0,base0,base1)
{
    lda #byte0
    sta [dlist_next_byte],Y
    iny

    lda base0, X
    sta [dlist_next_byte],Y
    iny

    lda base1, X
    sta [dlist_next_byte],Y
    iny
}

// A = 2nd byte
inline add_inst_2_first(op)
{
    ldy #1
    sta [dlist_next_byte],Y
    iny

    lda #op
    sta dlist_cmd_first_inst_byte

    assign_16_16(dlist_cmd_first_inst_addr, dlist_next_byte)
}

inline add_inst_3_addr_first(byte0,addr)
{
    lda #byte0
    sta dlist_cmd_first_inst_byte
    ldy #1

    lda #lo(addr)
    sta [dlist_next_byte],Y
    iny

    lda #hi(addr)
    sta [dlist_next_byte],Y
    iny

    assign_16_16(dlist_cmd_first_inst_addr, dlist_next_byte)
}

// number of bytes in A, will perform inc on dlist_next_byte
inline advance_next_byte()
{
    clc
    adc dlist_next_byte+0
    sta dlist_next_byte+0
    lda #0
    adc dlist_next_byte+1
    sta dlist_next_byte+1
}

function sendchr_finish_frame()
{
    ldx #9
    ldy #12
    stx cmd_size
    sty cmd_cycles

    check_for_space_and_cycles()

    lda #_ppu_ctl0
    add_inst_2_first($A5)   // lda zp:  3 cycles, 2 bytes

    lda #$49        // eor imm: 2 cycles, 2 bytes
    add_inst_2_immarg(CR_BACKADDR1000)

    lda #$85        // sta zp:  3 cycles, 2 bytes
    add_inst_2_immarg(_ppu_ctl0)

    add_inst_3_addr($8D,$2000)  // sta abs: 4 cycles, 3 bytes

    finalize_command()

    //assign_16i(dlist_cycles_left, 0)
}

/******************************************************************************/

// dlist processing during vblank
function process_dlist()
{
    sec // flag to know whether we've run an incomplete dlist

    ppu_ctl1_assign(#0) // disable rendering until we're done

    jmp dlist_start_jmp

    // this will ultimately be returned by an RTS in the IRQ handler
}

// from IRQ, when the end be reached
inline process_dlist_complete()
{
    // get rid of saved flags
    pla

    vram_clear_address()
    ppu_ctl1_assign(#CR_BACKVISIBLE)    // reenable rendering

    // back up to one past the BRK, if this was a complete dlist
    ldx #1

    if (carry)
    {
        // this was an incomplete dlist, reset cycle counter
        lda #1
        sta dlist_reset_cycles

        // back up to where the BRK was
        ldx #2

        inc_16(incomplete_vblanks)
    }
    else
    {
        inc_16(complete_vblanks)
    }
    stx irq_temp

    pla
    sec
    sbc irq_temp
    sta dlist_start+0
    pla
    sbc #0
    sta dlist_start+1

    rts // actually return from process_dlist
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
    13 + 14,
    13 + 23,
    13 + 35,
    16 + (7 * 4),
    16 + (7 * 5),
    16 + (7 * 6),
    16 + (7 * 7),
    13 + 59
}

// 22 + 9 * lines + zp_writer
byte cmd_X_update_lines_cycles[8] = {
    16 + 18,
    16 + 30,
    16 + 46,
    22 + (9 * 4) + (11 + (6 * 4) + 6),
    22 + (9 * 5) + (11 + (6 * 5) + 6),
    22 + (9 * 6) + (11 + (6 * 6) + 6),
    22 + (9 * 7) + (11 + (6 * 7) + 6),
    16 + 140
}

function cmd_X_update_lines()
{
    //
    ldx cmd_lines
    lda cmd_X_update_lines_bytes-1, X
    sta cmd_size
    lda cmd_X_update_lines_cycles-1, X
    sta cmd_cycles

    check_for_space_and_cycles()

    lda cmd_addr+0
    ora cmd_start
    add_inst_2_first($A0)   // ldy imm: 2 cycles, 2 bytes

    lda #$A2        // ldx imm: 2 cycles, 2 bytes
    add_inst_2_ldarg(cmd_addr+1)

    add_inst_3_addr($8E,$2006)  // stx abs: 4 cycles, 3 bytes

    add_inst_3_addr($8C,$2006)  // sty abs: 4 cycles, 3 bytes

    // dummy read
    add_inst_3_addr($AD,$2007)  // lda abs: 4 cycles, 3 bytes

    ldx cmd_lines
    lda cmd_X_update_lines_jmp_tab_0, X
    sta tmp_addr+0
    lda cmd_X_update_lines_jmp_tab_1, X
    sta tmp_addr+1
    ldx cmd_start
    jmp [tmp_addr]

//cmd_X_update_lines_8:
//    cmd_X_2007_sta(zp_immed_0)  // 9 cycles, 7 bytes * lines
 cmd_X_update_lines_7:
    cmd_X_2007_sta(zp_immed_1)
    inx
 cmd_X_update_lines_6:
    cmd_X_2007_sta(zp_immed_2)
    inx
 cmd_X_update_lines_5:
    cmd_X_2007_sta(zp_immed_3)
    inx
cmd_X_update_lines_4:
    cmd_X_2007_sta(zp_immed_4)
    inx
//cmd_X_update_lines_3:
    cmd_X_2007_sta(zp_immed_5)
    inx
//cmd_X_update_lines_2:
    cmd_X_2007_sta(zp_immed_6)
    inx
//cmd_X_update_lines_1:    
    cmd_X_2007_sta(zp_immed_7)

    ldx cmd_lines
    add_inst_3_lookup($20,(zp_writer_lines_tab_0-1),(zp_writer_lines_tab_1-1)) // jsr 6 + ?? cycles, 3 bytes

    finalize_command()
}

// 18 cycles, 14 bytes
function cmd_X_update_lines_1()
{
    cmd_X_2007(cmd_byte+0)    // 6 cycles, 5 bytes

    add_inst_3_addr($8E,$2006)  // stx abs: 4 cycles, 3 bytes
    add_inst_3_addr($8C,$2006)  // sty abs: 4 cycles, 3 bytes
    add_inst_3_addr($8D,$2007)  // sta abs: 4 cycles, 3 bytes

    finalize_command()
}

// 30 cycles, 23 bytes
function cmd_X_update_lines_2()
{
    add_inst_3_addr($8E,$2006)  // stx abs: 4 cycles, 3 bytes

    cmd_X_2007(cmd_byte+0)  // 6 cycles, 5 bytes

    lda #$AA // tax: 2 cycles, 1 byte
    add_inst_1() 

    cmd_X_2007(cmd_byte+1)  // 6 cycles, 5 bytes

    add_inst_3_addr($8C,$2006)  // sty abs: 4 cycles, 3 bytes

    add_inst_3_addr($8E,$2007)  // stx abs: 4 cycles, 3 bytes
    add_inst_3_addr($8D,$2007)  // sta abs: 4 cycles, 3 bytes

    finalize_command()
}

// 46 cycles, 35 bytes
function cmd_X_update_lines_3()
{
    add_inst_3_addr($8E,$2006)  // stx abs: 4 cycles, 3 bytes

    cmd_X_2007_sta(zp_immed_5)  // 9 cycles, 7 bytes

    cmd_X_2007(cmd_byte+1)  // 6 cycles, 5 bytes

    lda #$AA // tax: 2 cycles, 1 byte
    add_inst_1() 

    cmd_X_2007(cmd_byte+2)  // 6 cycles, 5 bytes

    add_inst_3_addr($8C,$2006)  // sty abs: 4 cycles, 3 bytes

    lda #$A4    // ldy zp: 3 cycles, 2 bytes
    add_inst_2_immarg(zp_immed_5)

    add_inst_3_addr($8C,$2007)  // sty abs: 4 cycles, 3 bytes
    add_inst_3_addr($8E,$2007)  // stx abs: 4 cycles, 3 bytes
    add_inst_3_addr($8D,$2007)  // sta abs: 4 cycles, 3 bytes

    finalize_command()
}

// 140 cycles, 59 bytes
// no faster, but avoids extra work when generating
function cmd_X_update_lines_8()
{
    cmd_X_2007_sta_fixed(zp_immed_0,cmd_byte+0)  // 9 cycles, 7 bytes * 8
    cmd_X_2007_sta_fixed(zp_immed_1,cmd_byte+1)
    cmd_X_2007_sta_fixed(zp_immed_2,cmd_byte+2)
    cmd_X_2007_sta_fixed(zp_immed_3,cmd_byte+3)
    cmd_X_2007_sta_fixed(zp_immed_4,cmd_byte+4)
    cmd_X_2007_sta_fixed(zp_immed_5,cmd_byte+5)
    cmd_X_2007_sta_fixed(zp_immed_6,cmd_byte+6)
    cmd_X_2007_sta_fixed(zp_immed_7,cmd_byte+7)

    add_inst_3_addr($20,zp_writer) // jsr 6 + 62 cycles, 3 bytes
    finalize_command()
}

byte cmd_X_update_lines_jmp_tab_0[9] = {
    0,
    lo(cmd_X_update_lines_1),
    lo(cmd_X_update_lines_2),
    lo(cmd_X_update_lines_3),
    lo(cmd_X_update_lines_4),
    lo(cmd_X_update_lines_5),
    lo(cmd_X_update_lines_6),
    lo(cmd_X_update_lines_7),
    lo(cmd_X_update_lines_8)
}

byte cmd_X_update_lines_jmp_tab_1[9] = {
    0,
    hi(cmd_X_update_lines_1),
    hi(cmd_X_update_lines_2),
    hi(cmd_X_update_lines_3),
    hi(cmd_X_update_lines_4),
    hi(cmd_X_update_lines_5),
    hi(cmd_X_update_lines_6),
    hi(cmd_X_update_lines_7),
    hi(cmd_X_update_lines_8)
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
    ldx cmd_lines
    lda cmd_set_lines_bytes-1, X
    sta cmd_size
    lda cmd_set_lines_cycles-1, X
    sta cmd_cycles

    check_for_space_and_cycles()

    lda cmd_addr+0
    ora cmd_start
    add_inst_2_first($A0)   // ldy imm: 2 cycles, 2 bytes

    lda #$A2        // ldx imm: 2 cycles, 2 bytes
    add_inst_2_ldarg(cmd_addr+1)

    add_inst_3_addr($8E,$2006)  // stx abs: 4 cycles, 3 bytes

    add_inst_3_addr($8C,$2006)  // sty abs: 4 cycles, 3 bytes

    ldx cmd_lines
    lda cmd_set_lines_tab_0, X
    sta tmp_addr+0
    lda cmd_set_lines_tab_1, X
    sta tmp_addr+1

    txa
    clc
    adc cmd_start
    tax

    jmp [tmp_addr]

 cmd_set_8_lines:
    cmd_imm_2007_X(cmd_byte-8)    // 6 cycles, 5 bytes * lines
 cmd_set_7_lines:
    cmd_imm_2007_X(cmd_byte-7)
 cmd_set_6_lines:
    cmd_imm_2007_X(cmd_byte-6)
 cmd_set_5_lines:
    cmd_imm_2007_X(cmd_byte-5)
 cmd_set_4_lines:
    cmd_imm_2007_X(cmd_byte-4)
 cmd_set_3_lines:
    cmd_imm_2007_X(cmd_byte-3)
 cmd_set_2_lines:
    cmd_imm_2007_X(cmd_byte-2)
 cmd_set_1_line:
    cmd_imm_2007_X(cmd_byte-1)

    finalize_command()
}

byte cmd_set_lines_tab_0[9] = {
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
byte cmd_set_lines_tab_1[9] = {
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
    ldx cmd_lines
    lda cmd_clr_lines_bytes-1, X
    sta cmd_size
    lda cmd_clr_lines_cycles-1, X
    sta cmd_cycles

    check_for_space_and_cycles()

    lda cmd_addr+0
    ora cmd_start
    add_inst_2_first($A0)   // ldy imm: 2 cycles, 2 bytes

    lda #$A2        // ldx imm: 2 cycles, 2 bytes
    add_inst_2_ldarg(cmd_addr+1)

    add_inst_3_addr($8E,$2006)  // stx abs: 4 cycles, 3 bytes

    add_inst_3_addr($8C, $2006) // sty abs: 4 cycles, 3 bytes

    lda #$A9        // lda imm: 2 cycles, 2 bytes
    add_inst_2_immarg(0)

    ldx cmd_lines
    lda cmd_clr_lines_tab_0, X
    sta tmp_addr+0
    lda cmd_clr_lines_tab_1, X
    sta tmp_addr+1

    jmp [tmp_addr]

 cmd_clr_8_lines:
    cmd_sta_2007()  // 4 cycles, 3 bytes * lines
 cmd_clr_7_lines:
    cmd_sta_2007()
 cmd_clr_6_lines:
    cmd_sta_2007()
 cmd_clr_5_lines:
    cmd_sta_2007()
 cmd_clr_4_lines:
    cmd_sta_2007()
 cmd_clr_3_lines:
    cmd_sta_2007()
 cmd_clr_2_lines:
    cmd_sta_2007()
 cmd_clr_1_line:
    cmd_sta_2007()

    finalize_command()
}

byte cmd_clr_lines_tab_0[9] = {
    0,
    lo(cmd_clr_1_line),
    lo(cmd_clr_2_lines),
    lo(cmd_clr_3_lines),
    lo(cmd_clr_4_lines),
    lo(cmd_clr_5_lines),
    lo(cmd_clr_6_lines),
    lo(cmd_clr_7_lines),
    lo(cmd_clr_8_lines)
}

byte cmd_clr_lines_tab_1[9] = {
    0,
    hi(cmd_clr_1_line),
    hi(cmd_clr_2_lines),
    hi(cmd_clr_3_lines),
    hi(cmd_clr_4_lines),
    hi(cmd_clr_5_lines),
    hi(cmd_clr_6_lines),
    hi(cmd_clr_7_lines),
    hi(cmd_clr_8_lines)
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

    lda cmd_addr+0
    add_inst_2_first($A0)   // ldy imm: 2 cycles, 2 bytes

    ldx cmd_addr+1
    lda #$A2        // ldx imm: 2 cycles, 2 bytes
    add_inst_2_ldargX(flip_nametable)

    add_inst_3_addr($8E,$2006)   // stx abs: 4 cycles, 3 bytes

    add_inst_3_addr($8C, $2006)  // sty abs: 4 cycles, 3 bytes

    // dummy read
    add_inst_3_addr($AD,$2007)   // lda abs: 4 cycles, 3 bytes

    lda cmd_lines
    asl A
    asl A
    asl A
    ora cmd_start
    tax
    lda rangetab-8, X
    sta cmd_size

    cmd_maybe_X_2007_sta(cmd_byte+0, zp_immed_0) // 9 cycles, 7 bytes * lines +
    cmd_maybe_X_2007_sta(cmd_byte+1, zp_immed_1) // 7 cycles, 5 bytes * (8 - lines)
    cmd_maybe_X_2007_sta(cmd_byte+2, zp_immed_2)
    cmd_maybe_X_2007_sta(cmd_byte+3, zp_immed_3)
    cmd_maybe_X_2007_sta(cmd_byte+4, zp_immed_4)
    cmd_maybe_X_2007_sta(cmd_byte+5, zp_immed_5)
    cmd_maybe_X_2007_sta(cmd_byte+6, zp_immed_6)
    cmd_maybe_X_2007_sta(cmd_byte+7, zp_immed_7)

    lda #$A2        // ldx imm: 2 cycles, 2 bytes
    add_inst_2_ldarg(cmd_addr+1)

    add_inst_3_addr($20,zp_writer)  // jsr: 6 + 62 cycles, 3 bytes

    finalize_command()
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

    lda cmd_addr+0
    add_inst_2_first($A0)   // ldy imm: 2 cycles, 2 bytes

    lda #$A2        // ldx imm: 2 cycles, 2 bytes
    add_inst_2_ldarg(cmd_addr+1)

    add_inst_3_addr($8E,$2006)  // stx abs: 4 cycles, 3 bytes

    add_inst_3_addr($8C,$2006)  // sty abs: 4 cycles, 3 bytes

    lda #$A0        // ldy imm: 2 cycles, 2 bytes
    add_inst_2_immarg(0)

    lda cmd_lines
    asl A
    asl A
    asl A
    ora cmd_start
    tax
    lda rangetab-8, X
    sta cmd_size

    cmd_2007_maybe_Y_lda_A_2007_sta(cmd_byte+0) // 6 cycles, 5 bytes * lines +
    cmd_2007_maybe_Y_lda_A_2007_sta(cmd_byte+1) // 4 cycles, 3 bytes * (8 - lines)
    cmd_2007_maybe_Y_lda_A_2007_sta(cmd_byte+2)
    cmd_2007_maybe_Y_lda_A_2007_sta(cmd_byte+3)
    cmd_2007_maybe_Y_lda_A_2007_sta(cmd_byte+4)
    cmd_2007_maybe_Y_lda_A_2007_sta(cmd_byte+5)
    cmd_2007_maybe_Y_lda_A_2007_sta(cmd_byte+6)
    cmd_2007_maybe_Y_lda_A_2007_sta(cmd_byte+7)

    finalize_command()
}

inline cmd_X_2007_sta(dst)
{
    add_inst_3_addr($AD,$2007)  // lda abs: 4 cycles, 3 bytes

    lda cmd_op  // ora or and imm: 2 cycles, 2 bytes
    add_inst_2_ldargX(cmd_byte)

    lda #$85    // sta zp: 3 cycles, 2 bytes
    add_inst_2_immarg(dst)
}

inline cmd_X_2007_sta_fixed(dst,src)
{
    add_inst_3_addr($AD,$2007)  // lda abs: 4 cycles, 3 bytes

    lda cmd_op  // ora or and imm: 2 cycles, 2 bytes
    add_inst_2_ldarg(src)

    lda #$85    // sta zp: 3 cycles, 2 bytes
    add_inst_2_immarg(dst)
}

inline cmd_X_2007(src)
{
    add_inst_3_addr($AD,$2007)  // lda abs: 4 cycles, 3 bytes

    lda cmd_op  // ora or and imm: 2 cycles, 2 bytes
    add_inst_2_ldargX(src)
}

inline cmd_imm_2007_X(src)
{
    add_inst_2_X($A9, src)  // lda imm: 2 cycles, 2 bytes

    add_inst_3_addr($8D,$2007)  // sta abs: 4 cycles, 3 bytes
}

inline cmd_maybe_X_2007_sta(src, dst)
{
    add_inst_3_addr($AD,$2007)  // lda abs: 4 cycles, 3 bytes

    lsr cmd_size // operation line range
    if (carry)
    {
        lda cmd_op  // ora or and imm: 2 cycles, 2 bytes
        add_inst_2_ldarg(src)
    }

    lda #$85    // sta zp: 3 cycles, 2 bytes
    add_inst_2_immarg(dst)
}

inline cmd_2007_maybe_Y_lda_A_2007_sta(src)
{
    lda #$8C    // sty abs: 4 cycles, 3 bytes

    lsr cmd_size // operation line range
    if (carry)
    {
        lda #$A9    // lda imm: 2 cycles, 2 bytes
        add_inst_2_ldarg(src)

        lda #$8D    // sta abs: 4 cycles, 3 bytes
    }

    add_inst_3_A_addr($2007)
}

inline cmd_sta_2007()
{
    add_inst_3_addr($8D,$2007)  // sta abs: 4 cycles, 3 bytes
}

// cmd_addr = VRAM address
function cmd_tile_clear()
{
    ldx #9
    ldy #58
    stx cmd_size
    sty cmd_cycles
    check_for_space_and_cycles()

    
    lda #0
    add_inst_2_first($A9)   // lda imm: 2 cycles, 2 bytes

    lda #$A0    // ldy imm: 2 cycles, 2 bytes
    add_inst_2_ldarg(cmd_addr+0)

    lda #$A2    // ldx imm: 2 cycles, 2 bytes
    add_inst_2_ldarg(cmd_addr+1)

    add_inst_3_addr($20, vram_fill_tile) // jsr: 6 + 46 cycles, 3 bytes

    finalize_command()
}

// cmd_addr = VRAM address
function cmd_tile_copy()
{
    ldx #7
    ldy #149
    stx cmd_size
    sty cmd_cycles
    check_for_space_and_cycles()

    lda cmd_addr+0
    add_inst_2_first($A0)   // ldy imm: 2 cycles, 2 bytes

    lda #$A2    // ldx imm: 2 cycles, 2 bytes
    ldx cmd_addr+1
    add_inst_2_ldargX(flip_nametable)

    add_inst_3_addr($20, vram_copy_tile) // jsr: 6 + 139 cycles, 3 bytes

    finalize_command()
}

// cmd_start = cache address
function cmd_tile_cache_write()
{
    ldx #50
    ldy #60
    stx cmd_size
    sty cmd_cycles
    check_for_space_and_cycles()

    lda cmd_addr+0
    add_inst_2_first($A0)   // ldy imm: 2 cycles, 2 bytes

    lda #$A2    // ldx imm: 2 cycles, 2 bytes
    add_inst_2_ldarg(cmd_addr+1)

    add_inst_3_addr($8E,$2006)  // stx abs: 4 cycles, 3 bytes
    add_inst_3_addr($8C,$2006)  // sty abs: 4 cycles, 3 bytes

    lda cmd_start
    and #~7
    tax

    cmd_imm_2007_X(tile_cache+0)  // 6 cycles, 5 bytes * 8
    cmd_imm_2007_X(tile_cache+1)
    cmd_imm_2007_X(tile_cache+2)
    cmd_imm_2007_X(tile_cache+3)
    cmd_imm_2007_X(tile_cache+4)
    cmd_imm_2007_X(tile_cache+5)
    cmd_imm_2007_X(tile_cache+6)
    cmd_imm_2007_X(tile_cache+7)

    finalize_command()
}

byte cmd_tile_cache_write_lines_bytes[8] = {
    10 + (5*1),
    10 + (5*2),
    10 + (5*3),
    10 + (5*4),
    10 + (5*5),
    10 + (5*6),
    10 + (5*7),
    10 + (5*8)
}

byte cmd_tile_cache_write_lines_cycles[8] = {
    12 + (6*1),
    12 + (6*2),
    12 + (6*3),
    12 + (6*4),
    12 + (6*5),
    12 + (6*6),
    12 + (6*7),
    12 + (6*8)
}

// cmd_start = cache address
function cmd_tile_cache_write_lines()
{
    ldx cmd_lines
    lda cmd_tile_cache_write_lines_bytes-1, X
    sta cmd_size
    lda cmd_tile_cache_write_lines_cycles-1, X
    sta cmd_cycles
    check_for_space_and_cycles()

    lda cmd_start
    and #7
    ora cmd_addr+0
    add_inst_2_first($A0)   // ldy imm: 2 cycles, 2 bytes

    lda #$A2    // ldx imm: 2 cycles, 2 bytes
    add_inst_2_ldarg(cmd_addr+1)

    add_inst_3_addr($8E,$2006)  // stx abs: 4 cycles, 3 bytes
    add_inst_3_addr($8C,$2006)  // sty abs: 4 cycles, 3 bytes

    ldx cmd_lines
    lda cmd_cache_write_lines_tab_0, X
    sta tmp_addr+0
    lda cmd_cache_write_lines_tab_1, X
    sta tmp_addr+1

    txa
    clc
    adc cmd_start
    tax

    jmp [tmp_addr]

 cmd_cache_write_8_lines:
    cmd_imm_2007_X(tile_cache-8)  // 6 cycles, 5 bytes * 8
 cmd_cache_write_7_lines:
    cmd_imm_2007_X(tile_cache-7)
 cmd_cache_write_6_lines:
    cmd_imm_2007_X(tile_cache-6)
 cmd_cache_write_5_lines:
    cmd_imm_2007_X(tile_cache-5)
 cmd_cache_write_4_lines:
    cmd_imm_2007_X(tile_cache-4)
 cmd_cache_write_3_lines:
    cmd_imm_2007_X(tile_cache-3)
 cmd_cache_write_2_lines:
    cmd_imm_2007_X(tile_cache-2)
 cmd_cache_write_1_line:
    cmd_imm_2007_X(tile_cache-1)

    finalize_command()
}

byte cmd_cache_write_lines_tab_0[9] = {
    0,
    lo(cmd_cache_write_1_line),
    lo(cmd_cache_write_2_lines),
    lo(cmd_cache_write_3_lines),
    lo(cmd_cache_write_4_lines),
    lo(cmd_cache_write_5_lines),
    lo(cmd_cache_write_6_lines),
    lo(cmd_cache_write_7_lines),
    lo(cmd_cache_write_8_lines)
}

byte cmd_cache_write_lines_tab_1[9] = {
    0,
    hi(cmd_cache_write_1_line),
    hi(cmd_cache_write_2_lines),
    hi(cmd_cache_write_3_lines),
    hi(cmd_cache_write_4_lines),
    hi(cmd_cache_write_5_lines),
    hi(cmd_cache_write_6_lines),
    hi(cmd_cache_write_7_lines),
    hi(cmd_cache_write_8_lines)
}
