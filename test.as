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

    lda #$0
    sta cmd_addr+0
    lda #$0
    sta cmd_addr+1
    lda #$FF
    sta cmd_byte
    cmd_or_one_byte()

    lda #$C
    sta cmd_addr+0
    lda #$0
    sta cmd_addr+1
    lda #$FF
    sta cmd_byte
    cmd_or_one_byte()

    lda #$8
    sta cmd_addr+0
    lda #$0
    sta cmd_addr+1
    lda #$10
    sta cmd_byte+0
    sta cmd_byte+1
    sta cmd_byte+2
    sta cmd_byte+3
    sta cmd_byte+4
    sta cmd_byte+5
    sta cmd_byte+6
    sta cmd_byte+7
    cmd_or_tile_update()

    lda #$F
    sta cmd_addr+0
    lda #$0
    sta cmd_addr+1
    lda #$C3
    sta cmd_byte
    cmd_or_one_byte()

    lda #$0
    sta cmd_addr+0
    lda #$0
    sta cmd_addr+1
    lda #$01
    sta cmd_byte+0
    asl A
    sta cmd_byte+1
    asl A
    sta cmd_byte+2
    asl A
    sta cmd_byte+3
    asl A
    sta cmd_byte+4
    asl A
    sta cmd_byte+5
    asl A
    sta cmd_byte+6
    asl A
    sta cmd_byte+7
    cmd_or_tile_update()

    sendchr_finish_frame()
    tracktiles_finish_frame()

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
