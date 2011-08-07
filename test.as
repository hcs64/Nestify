#ines.mapper        "none"
#ines.mirroring     "Horizontal"
#ines.battery       "no"
#ines.trainer       "no"
#ines.fourscreen    "no"

#rom.banksize 16K

#include "nes.h"
#include "std.h"

#include "mem.as"

#rom.bank BANK_MAIN_ENTRY
#rom.org 0xC000

#include "tiles.as"
#include "sendchr.as"

#interrupt.start    main
#interrupt.irq      int_irq
#interrupt.nmi      int_nmi

interrupt.irq int_irq()
{
}

interrupt.nmi int_nmi()
{
    pha
    txa
    pha
    tya
    pha

    ldx dlist_count
    beq no_dlists

    dex
    stx dlist_count

    ldx dlist_read_idx
    x_assign_16_16(dlist_start, dlists)

    // DEBUG: clear out visited dlists
    lda #0
    sta dlists+0, X
    sta dlists+1, X

    txa
    clc
    adc #2
    and #MAX_DLISTS_MOD_MASK
    sta dlist_read_idx

    lda PPU.STATUS
    jsr dlist_start_jmp

    jmp done_dlists

no_dlists:
    // may want to do an error message or count here

done_dlists:

    vram_clear_address()

    pla
    tay
    pla
    tax
    pla
}

inline system_initialize_custom()
{
    disable_decimal_mode()
    disable_interrupts()
    reset_stack()

    // clear the registers
    lda  #0

    sta  PPU.CNT0
    sta  PPU.CNT1

    sta  _ppu_ctl0
    sta  _ppu_ctl1
    sta  _joypad0

    sta  PPU.BG_SCROLL
    sta  PPU.BG_SCROLL

    sta  PCM_CNT
    sta  PCM_VOLUMECNT
    sta  SND_CNT

    lda  #0xC0
    sta  joystick.cnt1

    // wait for PPU to turn on
    bit PPU.STATUS
vwait1:
    bit PPU.STATUS
    bpl vwait1
vwait2:
    bit PPU.STATUS
    bpl vwait2
}

/******************************************************************************/

interrupt.start noreturn main()
{
    system_initialize_custom()

    clear_vram()
    init_vram()
    init_tracktiles()
    init_sendchr()
    lda #0
    sta cur_nametable_page

    // turn everything on
    vblank_wait()
    vram_clear_address()
    ppu_ctl0_assign(#CR_NMI|CR_BACKADDR1000)
    //ppu_ctl1_assign(#CR_BACKVISIBLE|CR_SPRITESVISIBLE|CR_BACKNOCLIP|CR_SPRNOCLIP)
    ppu_ctl1_assign(#CR_BACKVISIBLE)

    // should do random pixels here

    forever {
        // add odds
        ldx #100
        do {
            dex
            stx test_lines

            ldy #0
            lda #$FF
            or_line()

            ldx test_lines
            dex
        } while (not zero)

        finish_frame()

        ldx #20
        do {
            stx test_frames

            // add evens, remove odds
            ldx #100
            do {
                stx test_lines

                ldy #0
                lda #$FF
                or_line()

                ldx test_lines
                dex
                stx test_lines

                ldy #0
                lda #$0
                and_line()

                ldx test_lines
                dex
            } while (not zero)

            finish_frame()

            // remove evens, add odds
            ldx #100
            do {
                stx test_lines

                ldy #0
                lda #$0
                and_line()

                ldx test_lines
                dex
                stx test_lines

                ldy #0
                lda #$FF
                or_line()

                ldx test_lines
                dex
            } while (not zero)

            finish_frame()

            ldx test_frames
            dex
        } while (not zero)

        // remove odds
        ldx #100
        do {
            dex
            stx test_lines

            ldy #0
            lda #$0
            and_line()

            ldx test_lines
            dex
        } while (not zero)
    }
}

/******************************************************************************/

function clear_vram()
{
    vram_clear_address()

    lda #0
    ldy #0x30
    do {
        ldx #0x80
        do {
            sta PPU.IO
            sta PPU.IO
            dex
        } while (not zero)
        dey
    } while (not zero)
}

/******************************************************************************/

function init_vram()
{
    // reset latch
    lda PPU.STATUS

    init_palette()
    init_attrs()
    init_names()
}

function init_palette()
{
    // Setup palette
    lda #hi(PAL_0_ADDRESS)
    sta PPU.ADDRESS
    lda #lo(PAL_0_ADDRESS)
    sta PPU.ADDRESS

    // palette 0
    ldx #0x0F   // bg
    ldy #0x1A   // fg
    stx PPU.IO  // 00: bg
    sty PPU.IO  // 01: fg
    stx PPU.IO  // 10: bg
    sty PPU.IO  // 11: fg

    lda #hi(PAL_0_ADDRESS+4+1)
    sta PPU.ADDRESS
    lda #lo(PAL_0_ADDRESS+4+1)
    sta PPU.ADDRESS

    // palette 1
    stx PPU.IO  // 01: bg
    sty PPU.IO  // 10: fg
    sty PPU.IO  // 11: fg
}


/******************************************************************************/

function init_attrs()
{
    lda #hi(ATTRIBUTE_TABLE_0_ADDRESS)
    sta PPU.ADDRESS
    lda #lo(ATTRIBUTE_TABLE_0_ADDRESS)
    sta PPU.ADDRESS

    ldx #7
    do {
        ldy #4
        lda #0
        do {
            sta PPU.IO
            dey
        } while (not zero)

        ldy #4
        lda #%01010101
        do {
            sta PPU.IO
            dey
        } while (not zero)
        dex
    } while (not zero)
}

/******************************************************************************/

function init_names()
{
    lda #hi(NAME_TABLE_0_ADDRESS)
    sta PPU.ADDRESS
    lda #lo(NAME_TABLE_0_ADDRESS)
    sta PPU.ADDRESS

    // top margin
    ldx #4
    lda #0xFF
    do {
        ldy #32
        do {
            sta PPU.IO
            dey
        } while (not zero)
        dex
    } while (not zero)

    ldx #21
    lda #0
    sta tmp_byte2
    lda #0xFF
    do {
        stx tmp_byte

        // left margin
        ldy #4
        do {
            sta PPU.IO
            dey
        } while (not zero)

        // left half of bitmap
        ldy #12
        ldx tmp_byte2
        do {
            stx PPU.IO
            inx
            dey
        } while (not zero)

        // right half of bitmap
        ldy #12
        ldx tmp_byte2
        do {
            stx PPU.IO
            inx
            dey
        } while (not zero)
        stx tmp_byte2

        // right margin
        ldy #4
        do {
            sta PPU.IO
            dey
        } while (not zero)

        ldx tmp_byte
        dex
    } while (not zero)

    // bottom margin
    ldx #5
    lda #0xFF
    do {
        ldy #32
        do {
            sta PPU.IO
            dey
        } while (not zero)
        dex
    } while (not zero)

}

/******************************************************************************/

// top level update commands

// Y:X = line address (8x block addres + line offset)
function or_line()
{
    sta cmd_byte
    stx cmd_addr+0
    tya
    sta tmp_byte
    ora cur_nametable_page
    sta cmd_addr+1

    txa
    lsr tmp_byte
    ror A
    lsr tmp_byte
    ror A
    lsr tmp_byte
    ror A
    tax
    ldy tmp_byte

    add_prim()

    if (zero) {
        // tile is clean

        if (carry) {
            // no previous prim, set is ok
            cmd_set_one_byte()
        } else {
            // need to update (just this byte)
            cmd_or_one_byte()
        }
    }
    else
    {
        // tile is dirty

        php

        lda cmd_addr+0
        and #7
        sta tmp_byte

        lda cmd_byte
        ldx #0

        ldy #7
        do {
            cpy tmp_byte
            if (equal)
            {
                sta cmd_byte, Y
            } else {
                stx cmd_byte, Y
            }
            dey
        } while (not minus)

        lda cmd_addr+0
        and #~7
        sta cmd_addr+0

        plp

        if (carry) {
            // no previous prim, set is ok
            cmd_tile_set()
        } else {
            // need to copy
            cmd_or_tile_copy()
        }
    }
}

// Y:X = line address (8x block addres + line offset)
function and_line()
{
    sta cmd_byte
    stx cmd_addr+0
    tya
    sta tmp_byte
    ora cur_nametable_page
    sta cmd_addr+1

    txa
    lsr tmp_byte
    ror A
    lsr tmp_byte
    ror A
    lsr tmp_byte
    ror A
    tax
    ldy tmp_byte

    remove_prim()

    if (zero) {
        // tile is clean

        if (carry) {
            // no remaining prim, clear is ok
            lda #0
            sta cmd_byte
            cmd_set_one_byte()
        } else {
            // need to update (just this byte)
            cmd_and_one_byte()
        }
    }
    else
    {
        // tile is dirty

        php

        lda cmd_addr+0
        and #7
        sta tmp_byte

        lda cmd_byte
        ldx #0xFF

        ldy #7
        do {
            cpy tmp_byte
            if (equal)
            {
                sta cmd_byte, Y
            } else {
                stx cmd_byte, Y
            }
            dey
        } while (not minus)

        lda cmd_addr+0
        and #~7
        sta cmd_addr+0

        plp

        if (carry) {
            // no remaining prim, clear is ok
            cmd_tile_clear()
        } else {
            // need to copy
            cmd_and_tile_copy()
        }
    }
}

function finish_frame()
{
    tracktiles_finish_frame()
    sendchr_finish_frame()

    do {
        lda dlist_count
        cmp #1
    } while (not zero)

    //lda _ppu_ctl0
    //eor #CR_BACKADDR1000
    //sta _ppu_ctl0

    lda cur_nametable_page
    eor #0x10
    sta cur_nametable_page
}
