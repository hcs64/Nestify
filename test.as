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
#include "lines.as"

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

    lda PPU.STATUS

    process_dlists()

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
    // reset latch
    lda PPU.STATUS

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
/*
        lda #$0f
        or_lines()
        finish_frame()

        lda #$f0
        or_lines()
        finish_frame()

        lda #$f0
        and_lines()
        finish_frame()

        lda #$0f
        and_lines()
        finish_frame()
*/

        lda #$0f
        or_blocks()
        finish_frame()

        lda #$f0
        or_lines()
        finish_frame()

        lda #$f0
        and_blocks()
        finish_frame()

        lda #$0f
        and_lines()
        finish_frame()
/*
        lda #$0f
        or_lines()
        lda #$f0
        or_lines()
        finish_frame()

        lda #$f0
        and_lines()
        lda #$0f
        and_lines()
        finish_frame()
*/

    }
}

function and_blocks()
{
    block_loop(and_block)
}

function or_blocks()
{
    block_loop(or_block)
}

inline block_loop(cmd)
{
    ldx #8
    do {
        dex
        sta cmd_byte, X
    } while (not zero)

    ldx #32
    do {
        dex
        stx test_lines

        txa
        sta tmp_byte

        lda #0
        asl tmp_byte
        rol A
        asl tmp_byte
        rol A
        asl tmp_byte
        rol A
        asl tmp_byte
        rol A
        tay

        ldx tmp_byte
        cmd()

/*
        lda test_lines
        and #7
        if (zero)
        {
            finish_frame()
        }
        */

        ldx test_lines
    } while (not zero)
}

function and_lines()
{
    lines_loop(and_line)
}

function or_lines()
{
    lines_loop(or_line)
}

inline lines_loop(cmd)
{
    sta test_byte
    ldx #254
    do {
        dex
        stx test_lines

        txa
        and #~7
        asl A
        sta tmp_byte

        lda #0
        rol A
        tay

        txa
        and #7
        adc tmp_byte // c cleared by rol
        tax

        lda test_byte
        cmd()

        lda test_lines
        and #7
        if (zero)
        {
            finish_frame()
        }

        ldx test_lines
    } while (not zero)
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

