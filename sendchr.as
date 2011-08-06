#define MAX_NMI_CYCLES 2200

zp_writer_rom:
    stx PPU.ADDRESS
    sty PPU.ADDRESS
    lda #00 // 0
    sta PPU.IO
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
    rts
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
    assign_16i(dlist_next_byte, dlist_0+0x37C)

    // fill flip_nametable
    ldx #0x10
    ldy #0
    lda #0
    clc
    do {
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

// command size in A, blocks until space frees up
function check_for_space()
{
    sec // extra byte for possible RTS
    adc dlist_next_byte+0
    sta tmp_addr+0
    lda #0
    adc dlist_next_byte+1
    sta tmp_addr+1

space_retry_loop:
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

    // both start and end are less then read (or end is equal), no chance of
    // overlap or wraparound
    rts

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
    
    // if this is the first command, we're actually completely empty, not full
    lda dlist_cycles_left+0
    cmp #lo(MAX_NMI_CYCLES)
    bne space_stuck
    lda dlist_cycles_left+1
    cmp #hi(MAX_NMI_CYCLES)
    beq enough_space

space_stuck:
    // otherwise we're stuck, so we need to end this dlist even though we're
    // not at the NMI limit yet
    ldx dlist_count
    if (equal) {
        finalize_dlist()
        setup_new_dlist()
    }
    jmp space_retry_loop

enough_space:
}

// cycle count in A, creates new dlist or blocks if we're already at max
function check_for_cycles()
{
    //
    sta tmp_byte

cycles_retry_loop:

    lda dlist_cycles_left+0
    sec
    sbc tmp_byte
    sta dlist_cycles_left+0

    lda dlist_cycles_left+1
    sbc #0
    sta dlist_cycles_left+1

    if (minus) {
        finalize_dlist()
        setup_new_dlist()
        jmp cycles_retry_loop
    }
}

function finalize_dlist()
{
    // finalize the current dlist
    lda #$60    // RTS
    ldy #0
    sta [dlist_next_byte], Y

    inc dlist_count

    clc
    lda #1
    adc dlist_next_byte+0
    sta dlist_next_byte+0
    lda #0
    adc dlist_next_byte+1
    sta dlist_next_byte+1
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

// A = 1st byte, X = 2nd byte, tmp_byte = 3rd byte
function add_inst_3()
{
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

// number of byets in A, will perform inc and wrap on dlist_next_byte
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

    lda #$EA    // NOP
    ldx dlist_next_byte
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
    finalize_dlist()
    setup_new_dlist()
}

/******************************************************************************/

// VRAM access library

// Y = address low, X = address high, A = value to OR
// 38 cycles
function vram_or_copy()
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

/******************************************************************************/

// command generation

// cmd_addr = VRAM address
// cmd_byte = byte to OR
function cmd_or_one_byte()
{
    lda #9
    check_for_space()
    lda #50
    check_for_cycles()

    lda #$A0        // ldy imm: 2 cycles, 2 bytes
    ldx cmd_addr+0
    add_inst_2()

    lda #$A2        // ldx imm: 2 cycles, 2 bytes
    ldx cmd_addr+1
    add_inst_2()

    lda #$A9        // lda imm: 2 cycles, 2 bytes
    ldx cmd_byte
    add_inst_2()

    lda #$20        // jsr: 6 + 38 cycles, 3 bytes
    ldx #lo(vram_or_copy)
    ldy #hi(vram_or_copy)
    sty tmp_byte
    add_inst_3()
}
