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
    assign_16i(dlist_next_byte, dlist_0)

    // init dlists queue
    lda #0
    sta dlist_read_idx
    sta dlist_write_idx
    sta dlist_count

    setup_new_dlist()

    // begin rendering to pattern table 0
    lda #0
    sta this_frame_hi
    lda #$10
    sta other_frame_hi
}

// command size in A, blocks until space frees up
function check_for_space()
{
    sec // extra byte for possible RTS
    adc dlist_next_byte+0
    sta tmp_addr+0
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
    // note: if there are no dlists ready, the one we check against
    // here will be the one in progress.... we would then be stuck,
    // so we need to end this dlist even though we're not at the NMI
    // limit yet
    ldx dlist_count
    if (equal) {
        setup_new_dlist()
    }
    jmp space_retry_loop

enough_space:
}

// cycle count in A, creates new dlist or blocks if we're already at max
function check_for_cycles()
{
    //
    ldx dlist_cycles_left+1 // high
    if (zero) {
        cmp dlist_cycles_left+0 // low
        if (minus) {
            // finalize the current dlist
            lda #$0x60  // RTS
            sta [dlist_next_byte,X] // X is zero

            inc dlist_next_byte+0
            adc dlist_next_byte+1
            setup_new_dlist()
        }
    }
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
