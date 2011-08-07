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

    // turn everything on
    vblank_wait()
    vram_clear_address()
    ppu_ctl0_assign(#CR_NMI)
    //ppu_ctl1_assign(#CR_BACKVISIBLE|CR_SPRITESVISIBLE|CR_BACKNOCLIP|CR_SPRNOCLIP)
    ppu_ctl1_assign(#CR_BACKVISIBLE)

    // should do random pixels here

    ldy #0
    ldx #1
    lda #0x18
    and_line()

    ldy #0
    ldx #1
    lda #$FF
    or_line()

    ldy #0
    ldx #8
    lda #$F0
    or_line()

    ldy #0
    ldx #8
    lda #$07
    or_line()


    tracktiles_finish_frame()
    sendchr_finish_frame()

    forever {}
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
    sty cmd_addr+1
    sty tmp_byte

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
    sty cmd_addr+1
    sty tmp_byte

    txa
    lsr tmp_byte
    ror A
    lsr tmp_byte
    ror A
    lsr tmp_byte
    ror A
    tax
    ldy tmp_byte

#tell.bankoffset
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

