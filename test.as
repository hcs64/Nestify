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

    bresenham_VPX_test()
    finish_frame()

    forever {
/*
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

word test_right_adjust_rom[2] = {-( (8*2*11) - 8), (8*2)}

// vertical, positive X
function bresenham_VPX_test()
{
#define DX 100
#define DY 168
    lda #lo( (2*DX)-DY )
    sta test_err+0
    lda #hi( (2*DX)-DY )
    sta test_err+1

    lda #lo(2*DX)
    sta test_err_strt+0
    lda #hi(2*DX)
    sta test_err_strt+1

    lda #lo( (2*DX) - (2*DY) )
    sta test_err_diag+0
    lda #hi( (2*DX) - (2*DY) )
    sta test_err_diag+1

    // how many lines down to go
    lda #DY
    sta test_lines

    // y coordinate
    lda #0
    sta test_y
    sta test_x_block

    // index of the block we're writing to
    lda #0
    sta test_block+0
    sta test_block+1

    // pixel position
    lda #$80
    sta test_byte

    // TODO: proper pixel positioning, clearing beginning of first block

    forever {
        lda test_y
        tay
        iny
        sty test_y

        // plot!
        and #7
        tax
        lda test_byte
        sta cmd_byte, X

        // check if we're done with this block vertically
        tya
        and #7
        if (zero)
        {
            // yes, send it
            ldx test_block+0
            ldy test_block+1

            or_block()

            // move to next block down
            clc
            lda test_block+0
            adc #(12*8*2)
            sta test_block+0
            lda test_block+1
            adc #0
            sta test_block+1
        }

        // check if we're done with this line
        dec test_lines
        // TODO: need to clear out and send the rest of the block
        beq blt_done

        // decision: go right?
        ldx #0
        bit test_err+1
        if (not minus)
        {

            // go right
            lsr test_byte
            if (carry)
            {
                // wrap pixel around
                ror test_byte

                // check if this isn't a new block
                lda test_y
                and #7
                if (not zero)
                {
                    // we had already written to the current block

                    // clean out the rest of it
                    tay
                    lda #0
                    do {
                        sta cmd_byte, Y
                        iny
                        cpy #8
                    } while (not equal)

                    // send it
                    ldx test_block+0
                    ldy test_block+1

                    or_block()

                    // now clean out our part
                    lda test_y
                    and #7
                    tax
                    lda #0
                    do {
                        sta cmd_byte-1, X
                        dex
                    } while (not zero)
                }

                // move to next block right
                inc test_x_block
                lda test_x_block
                sec
                sbc #12
                tax

                if (not equal)
                {
                    // straightforward adjust (8*2)
                    ldx #2
                }
                
                clc
                lda test_block+0
                adc test_right_adjust_rom+0, X
                sta test_block+0
                lda test_block+1
                adc test_right_adjust_rom+1, X
                sta test_block+1
            }

            ldx #2
        }

        // adjust error
        clc
        lda test_err+0
        adc test_err_strt+0, X
        sta test_err+0
        lda test_err+1
        adc test_err_strt+1, X
        sta test_err+1
    }

blt_done:
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

