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

    // init dlist_start (back of ring buf)
    lda #lo(dlist_0+DLIST_SIZE)
    sta dlist_start+0
    lda #hi(dlist_0+DLIST_SIZE)
    sta dlist_start+1

    // initialize the dlist to empty
    lda #$60    // rts
    sta dlist_0

    // init dlist_next_start (front of ring buf)
    lda #lo(dlist_0)
    sta dlist_next_start+0
    lda #hi(dlist_0)
    sta dlist_next_start+1

    // begin rendering to pattern table 0
    lda #0
    sta this_frame_hi
    lda #$10
    sta other_frame_hi
}

