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

#align 256
sintab:
#incbin "sintab.bin"

digits:
#incbin "digits.bin"

digitmap:
#incbin "digitmap.bin"

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

    vram_set_address_i( (NAME_TABLE_0_ADDRESS + (25*32) + 4 + 8) )

    // a little frames per frame display
        lda last_frame_time

        tay
        lda digitmap, Y
        vram_write_a()

        tya
        asl A
        asl A
        tay
        lda digitmap, Y
        vram_write_a()

        tya
        asl A
        asl A
        tay
        lda digitmap, Y
        vram_write_a()

        tya
        asl A
        asl A
        tay
        lda digitmap, Y
        vram_write_a()

    vram_clear_address()

    inc frame_counter

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

    sta frame_counter

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

    // test begins

    lda #0
    sta test_angle

        lda #1
        tax
        clc
        adc #$55
        tay

        lda sintab, X
        sta test_x0
        lda sintab+$100, X
        sta test_y0
        lda sintab, Y
        sta test_x1
        lda sintab+$100, Y
        sta test_y1
        bresenham_set()

        lda #1
        clc
        adc #$55
        tax
        clc
        adc #$55
        tay

        lda sintab, X
        sta test_x0
        lda sintab+$100, X
        sta test_y0
        lda #0 //sintab, Y
        sta test_x1
        lda #0 //sintab+$100, Y
        sta test_y1
        bresenham_set()

        lda #1
        clc
        adc #$aa
        tax
        clc
        adc #$55
        tay

        lda #0 //sintab, X
        sta test_x0
        lda #0 //sintab+$100, X
        sta test_y0
        lda sintab, Y
        sta test_x1
        lda sintab+$100, Y
        sta test_y1
        bresenham_set()

    forever {
        /*
        lda test_angle
        tax
        clc
        adc #$40
        tay

        lda sintab, X
        sta test_x0
        lda sintab+$100, X
        sta test_y0
        lda sintab, Y
        sta test_x1
        lda sintab+$100, Y
        sta test_y1
        bresenham_set()
        */

        lda test_angle
        clc
        adc #$40
        tax
        clc
        adc #$40
        tay

        lda sintab, X
        sta test_x0
        lda sintab+$100, X
        sta test_y0
        lda sintab, Y
        sta test_x1
        lda sintab+$100, Y
        sta test_y1
        bresenham_set()

        /*
        lda test_angle
        clc
        adc #$80
        tax
        clc
        adc #$40
        tay

        lda sintab, X
        sta test_x0
        lda sintab+$100, X
        sta test_y0
        lda sintab, Y
        sta test_x1
        lda sintab+$100, Y
        sta test_y1
        bresenham_set()
        */

        lda test_angle
        clc
        adc #$C0
        tax
        clc
        adc #$40
        tay

        lda sintab, X
        sta test_x0
        lda sintab+$100, X
        sta test_y0
        lda sintab, Y
        sta test_x1
        lda sintab+$100, Y
        sta test_y1
        bresenham_set()

        finish_frame()

        // clear
        /*
        lda test_angle
        tax
        clc
        adc #$40
        tay

        lda sintab, X
        sta test_x0
        lda sintab+$100, X
        sta test_y0
        lda sintab, Y
        sta test_x1
        lda sintab+$100, Y
        sta test_y1
        bresenham_clr()
        */

        lda test_angle
        clc
        adc #$40
        tax
        clc
        adc #$40
        tay

        lda sintab, X
        sta test_x0
        lda sintab+$100, X
        sta test_y0
        lda sintab, Y
        sta test_x1
        lda sintab+$100, Y
        sta test_y1
        bresenham_clr()

        /*
        lda test_angle
        clc
        adc #$80
        tax
        clc
        adc #$40
        tay

        lda sintab, X
        sta test_x0
        lda sintab+$100, X
        sta test_y0
        lda sintab, Y
        sta test_x1
        lda sintab+$100, Y
        sta test_y1
        bresenham_clr()
        */

        lda test_angle
        clc
        adc #$C0
        tax
        clc
        adc #$40
        tay

        lda sintab, X
        sta test_x0
        lda sintab+$100, X
        sta test_y0
        lda sintab, Y
        sta test_x1
        lda sintab+$100, Y
        sta test_y1
        bresenham_clr()

        lda test_angle
        clc
        adc #$6
        sta test_angle
    }
}

word test_right_adjust_rom[2] = {-( (8*2*11) - 8), (8*2)}
byte pixel_pos_rom[8] = {$80,$40,$20,$10,$08,$04,$02,$01}

function bresenham_set()
{
    bresenham_setup()

    txa
    if (minus)
    {
        tya
        if (zero)
        {
            bresenham_HPY_set()
        }
        else
        {
            bresenham_HNY_set()
        }
        rts
    }
    else
    {
        txa
        if (zero)
        {
            bresenham_VPX_set()
        }
        else
        {
            bresenham_VNX_set()
        }
    }
}

function bresenham_clr()
{
    bresenham_setup()

    txa
    if (minus)
    {
        tya
        if (zero)
        {
            bresenham_HPY_clr()
        }
        else
        {
            bresenham_HNY_clr()
        }
        rts
    }
    else
    {
        txa
        if (zero)
        {
            bresenham_VPX_clr()
        }
        else
        {
            bresenham_VNX_clr()
        }
    }
}

function bresenham_VPX_set()
{
    bresenham_VPX(or_block)
}
function bresenham_VPX_clr()
{
    bresenham_VPX(clr_block)
}
function bresenham_VNX_set()
{
    bresenham_VNX(or_block)
}
function bresenham_VNX_clr()
{
    bresenham_VNX(clr_block)
}
function bresenham_HPY_set()
{
    bresenham_HPY(or_line)
}
function bresenham_HPY_clr()
{
    bresenham_HPY(clr_line)
}
function bresenham_HNY_set()
{
    bresenham_HNY(or_line)
}
function bresenham_HNY_clr()
{
    bresenham_HNY(clr_line)
}

function bresenham_setup()
{
    ldy #0
    ldx #0

    stx test_err_strt+1

    sec
    lda test_x1
    sbc test_x0
    if (not carry) {
        eor #$ff
        clc
        adc #1
        inx
    }
    sta tmp_byte

    sec
    lda test_y1
    sbc test_y0
    if (not carry) {
        eor #$ff
        clc
        adc #1
        iny
    }

    cmp tmp_byte
    if (not carry)
    {
        // Y minor
        // compute 2*DMin (error adjustment when going straight)
        asl A
        sta test_err_strt+0
        rol test_err_strt+1

        // X major
        // compute DMaj (number of iterations)
        lda tmp_byte
        sta test_iters

        // always inc along the major axis
        txa
        if (not zero)
        {
            ldx test_x0
            lda test_x1
            sta test_x0
            stx test_x1

            ldx test_y0
            lda test_y1
            sta test_y0
            stx test_y1

            tya
            eor #1
            tay
        }

        ldx #$80
    }
    else
    {
        // Y major
        // compute DMaj (number of iterations)
        sta test_iters

        // X minor
        // compute 2*DMin (error adjustment when going straight)
        lda tmp_byte
        asl A
        sta test_err_strt+0
        rol test_err_strt+1

        // always inc along the major axis
        tya
        if (not zero)
        {
            ldy test_x0
            lda test_x1
            sta test_x0
            sty test_x1

            ldy test_y0
            lda test_y1
            sta test_y0
            sty test_y1

            txa
            eor #1
            tax
        }

        ldy #$80
    }

    // compute 2*DMin-DMaj (initial error)
    sec
    lda test_err_strt+0
    sbc test_iters
    sta test_err+0
    lda test_err_strt+1
    sbc #0
    sta test_err+1

    // compute 2*DMin-2*DMaj (error adjustment when going diagonally)
    sec
    lda test_err+0
    sbc test_iters
    sta test_err_diag+0
    lda test_err+1
    sbc #0
    sta test_err_diag+1

    // always cover the last pixel
    inc test_iters
}

function bresenham_common_setup()
{
    lda #0
    sta tmp_byte
    sta test_block+1

    // x coordinate in blocks
    lda test_x0
    lsr A
    lsr A
    lsr A
    sta test_x_block

    // calculate first block index
    lda test_x0
    and #~7
    cmp #(12*8)
    if (not minus)
    {
        sec
        sbc #( (12*8) - (8/2) )
    }
    asl A
    sta test_block+0
    rol test_block+1

    // y/8*8*2*12
    lda test_y0
    and #~7

    // +8y
    asl A
    rol tmp_byte
    asl A
    rol tmp_byte
    asl A
    rol tmp_byte
    tax
    clc
    adc test_block+0
    sta test_block+0
    lda tmp_byte
    adc test_block+1
    sta test_block+1

    // +16y
    txa
    asl A
    rol tmp_byte
    clc
    adc test_block+0
    sta test_block+0
    lda tmp_byte
    adc test_block+1
    sta test_block+1

    // pixel position
    lda test_x0
    and #7
    tax
    lda pixel_pos_rom, X
    sta test_byte
}

inline bresenham_HNY(cmd_fcn) {
    bresenham_H_common(cmd_fcn, bresenham_up_fcn)
}

inline bresenham_HPY(cmd_fcn) {
    bresenham_H_common(cmd_fcn, bresenham_down_fcn)
}

inline bresenham_down_fcn() {
    // move down a line
    inc test_y0
    inc test_block+0
    if (zero)
    {
        inc test_block+1
    }

    // check if we're done with this block vertically
    lda test_y0
    and #7
    if (zero)
    {
        // move to next block down, undo the test_block inc above
        clc
        lda test_block+0
        adc #( (12*8*2) - 8)
        sta test_block+0
        lda test_block+1
        adc #0
        sta test_block+1
    }
}
inline bresenham_up_fcn() {
    lda test_y0

    // move up a line
    dec test_y0
    ldx test_block+0
    if (zero)
    {
        dec test_block+1
    }
    dex
    stx test_block+0

    // check if we're done with this block vertically
    and #7
    if (zero)
    {
        // move to next block up, undo the test_block dec above
        sec
        lda test_block+0
        sbc #( (12*8*2) - 8)
        sta test_block+0
        lda test_block+1
        sbc #0
        sta test_block+1
    }
}

inline bresenham_H_common(cmd_fcn, updown_fcn) {
    bresenham_common_setup()

    lda test_y0
    and #7
    clc
    adc test_block+0
    sta test_block+0
    //lda test_block+1
    //adc #0
    //sta test_block+1

    // start with an empty buffer
    lda #0
    sta cmd_byte

    // do them columns
    forever {
        // plot!
        lda test_byte
        ora cmd_byte
        sta cmd_byte

        lsr test_byte

        // check if we're done with this block horizontally
        if (carry)
        {
            // wrap pixel around
            ror test_byte

            // send it
            ldx test_block+0
            ldy test_block+1
            lda cmd_byte

            cmd_fcn()

            // maybe that's all
            dec test_iters
            if (equal) {
                rts
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

            // clean out the line buffer
            lda #0
            sta cmd_byte
        }
        else
        {
            dec test_iters
            if (equal) {
                // send whatever we did so far

                ldx test_block+0
                ldy test_block+1
                lda cmd_byte

                cmd_fcn()

                rts
            }
        }

        // go up/down as well?
        ldx #0
        bit test_err+1
        if (not minus)
        {
            // check if this isn't a new line
            lda cmd_byte
            if (not zero)
            {
                // we had previously written to the current line

                // send it
                ldx test_block+0
                ldy test_block+1

                cmd_fcn()

                // clean out the line buffer
                lda #0
                sta cmd_byte
            }

            updown_fcn()

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
}

inline bresenham_VNX(cmd_fcn) {
    bresenham_V_common(cmd_fcn, bresenham_left_fcn, asl, rol)
}

inline bresenham_VPX(cmd_fcn) {
    bresenham_V_common(cmd_fcn, bresenham_right_fcn, lsr, ror)
}

inline bresenham_right_fcn() {
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

inline bresenham_left_fcn() {
    // move to next block left
    dec test_x_block
    lda test_x_block
    sec
    sbc #11
    tax

    if (not equal)
    {
        // straightforward adjust (8*2)
        ldx #2
    }
    
    sec
    lda test_block+0
    sbc test_right_adjust_rom+0, X
    sta test_block+0
    lda test_block+1
    sbc test_right_adjust_rom+1, X
    sta test_block+1
}

inline bresenham_V_common(cmd_fcn, rightleft_fcn, shift_op, rot_op) {
    bresenham_common_setup()

    // clear beginning of the block
    lda test_y0
    and #7
    tax
    lda #0
    dex
    if (not minus)
    {
        do {
            sta cmd_byte, X
            dex
        } while (not minus)
    }

    // do them rows
    forever {
        lda test_y0
        tay
        iny
        sty test_y0

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

            cmd_fcn()

            // maybe that's all
            dec test_iters
            if (equal) {
                rts
            }

            // move to next block down
            clc
            lda test_block+0
            adc #(12*8*2)
            sta test_block+0
            lda test_block+1
            adc #0
            sta test_block+1
        }
        else
        {
            dec test_iters
            if (equal) {
                // send the last block

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

                cmd_fcn()

                rts
            }
        }

        // go left/right as well?
        ldx #0
        bit test_err+1
        if (not minus)
        {
            // go right
            shift_op test_byte
            if (carry)
            {
                // wrap pixel around
                rot_op test_byte

                // check if this isn't a new block
                lda test_y0
                and #7
                if (not zero)
                {
                    // we had previously written to the current block

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

                    cmd_fcn()

                    // now clean out our part
                    lda test_y0
                    and #7
                    tax
                    lda #0
                    do {
                        sta cmd_byte-1, X
                        dex
                    } while (not zero)
                }

                rightleft_fcn()
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
    init_patterns()
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
    ldy #0x20   // fg
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

    // top rows, use palette 1, with the invisible bit 0
    lda #%01010101
    ldx #8
    do {
        sta PPU.IO
        dex
    } while (not zero)

    ldx #5
    do {
        // left margin, invisible bit 0
        lda #%01010101
        sta PPU.IO

        ldy #3
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

    // bottom strip
    ldy #%01010101
    sty PPU.IO

    // partially visible, for the status
    lda #%01010000
    ldx #3
    do {
        sta PPU.IO
        dex
    } while (not zero)

    ldx #(4+8)
    do {
        sty PPU.IO
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
    lda #0xFC
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
    lda #0xFC
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

function init_patterns()
{
    // fixed patterns
    assign_16i(tmp_addr, digits)
    vram_set_address_i( (TILES_WIDE * TILES_HIGH * 8 ) )
    ldx #4
    unpack_patterns()

    assign_16i(tmp_addr, digits)
    vram_set_address_i( ( (TILES_WIDE * TILES_HIGH * 8) + 0x1000 ) )
    ldx #4
    unpack_patterns()
}

function unpack_patterns()
{
    do {
        ldy #0
        do {
            vram_write_ind_y(tmp_addr)
            iny
            cpy #8
        } while (not equal)

        ldy #8
        lda #0
        do {
            vram_write_a()
            dey
        } while (not zero)

        clc
        lda #8
        adc tmp_addr+0
        sta tmp_addr+0
        lda #0
        adc tmp_addr+1
        sta tmp_addr+1

        dex
    } while (not equal)
}
