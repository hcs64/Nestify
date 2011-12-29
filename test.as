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

#define HOLD_DELAY 12
#define REPEAT_DELAY 3

#interrupt.start    main
#interrupt.irq      int_irq
#interrupt.nmi      int_nmi

#align 256
sintab:
#incbin "sintab.bin"

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

    vram_set_address_i( (NAME_TABLE_0_ADDRESS + (25*32) + 4) )

    // a little perf bar
    ldx last_frame_time
    sec
    lda #24
    sbc last_frame_time
    tay
    if (not carry)
    {
        ldx #24
        ldy #0
    }

    dex
    bmi done_fill
fill_loop:
    lda #0xFD
    dex
    bpl still_fill
    lda #0xFC
still_fill:
    sta $2007
    dex
    bpl fill_loop

done_fill:
    lda #0xFF
    dey
    bmi perf_bar_done
empty_loop:
    sta $2007
    dey
    bpl empty_loop
perf_bar_done:

    //
    inc frame_counter

    // done with PPU stuff
    vram_clear_address()

    // update controller once per frame
    reset_joystick()
    ldx #8
    do {
        lda JOYSTICK.CNT0
        lsr A
        if (carry)
        {
            php

            ldy hold_count_joypad0-1, X
            iny
            cpy #HOLD_DELAY
            if (not equal)
            {
                sty hold_count_joypad0-1, X
            }
            if (equal)
            {
                inc repeat_count_joypad0-1, X
                if (equal)
                {
                    // saturate at 255
                    dec repeat_count_joypad0-1, X
                }
            }

            plp
        }
        if (not carry)
        {
            lda #0
            sta hold_count_joypad0-1, X
            sta repeat_count_joypad0-1, X
        }
        rol _joypad0
        dex
    } while (not zero)

    lda _joypad0_acc
    ora _joypad0
    sta _joypad0_acc

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
    sta  _joypad0_acc

    sta frame_counter
    sta last_frame_time
    sta wasted_nmis
    sta total_dlists

    sta  PPU.BG_SCROLL
    sta  PPU.BG_SCROLL

    sta  PCM_CNT
    sta  PCM_VOLUMECNT
    sta  SND_CNT

    lda  #0xC0
    sta  joystick.cnt1

    // clear stats
    lda #0
    ldx #0x20
    do {
        sta 0x40, X
        dex
    } while (not zero)

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

    /*
    lda #0
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

    lda #$55
    tax
    clc
    adc #$55
    tay

    lda sintab, X
    //clc
    //adc #50
    sta test_x0
    lda sintab+$100, X
    sta test_y0
    lda sintab, Y
    sta test_x1
    lda sintab+$100, Y
    sta test_y1
    bresenham_set()

    lda #$aa
    tax
    clc
    adc #$56
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

    forever {}
    */

    //lda #$23
    lda #$e0
    sta test_angle
    lda #$6
    sta test_speed

    draw_triangle()

    forever {
        draw_square()

        finish_frame()

        clear_square()

        // turn, turn, turn
        lda _joypad0_acc
        tax
        eor last_joypad0
        stx last_joypad0
        and _joypad0_acc
        sta new_joypad0

        lda #0
        sta _joypad0_acc

        lda new_joypad0
        and #BUTTON_SELECT

        if (not zero)
        {
            clear_triangle()
            draw_triangle()
        }

        ldx #0
        process_button(BUTTON_UP, repeat_count_joypad0.UP, -6)
        process_button(BUTTON_DOWN, repeat_count_joypad0.DOWN, 6)
        process_button(BUTTON_LEFT, repeat_count_joypad0.LEFT, -1)
        process_button(BUTTON_RIGHT, repeat_count_joypad0.RIGHT, 1)

        lda new_joypad0
        and #BUTTON_START

        if (not zero)
        {
            lda test_speed
            if (zero)
            {
                lda #$6
            }
            else
            {
                lda #$0
            }
            sta test_speed
        }

        lda test_speed
        if (not zero)
        {
            tax
        }

        txa
        clc
        adc test_angle
        sta test_angle
        if (carry)
        {
            //forever {}
        }
    }
}

inline process_button(button_mask, button_repeat_count, delta)
{
    lda new_joypad0
    and #button_mask
    bne do_X_button

    lda button_repeat_count
    cmp #REPEAT_DELAY
    bmi skip_X_button

do_X_button:
    ldx #delta
    lda #0
    sta button_repeat_count

skip_X_button:
}

function clear_triangle() {
    do_triangle(bresenham_clr)
}
function draw_triangle() {
    do_triangle(bresenham_set)
}
function clear_square() {
    do_square(bresenham_clr)
}
function draw_square() {
    do_square(bresenham_set)
}

inline do_triangle(cmd_fcn)
{
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
    cmd_fcn()

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
    lda sintab, Y
    sta test_x1
    lda sintab+$100, Y
    sta test_y1
    cmd_fcn()

    lda #1
    clc
    adc #$aa
    tax
    clc
    lda #1
    //adc #$55
    tay

    lda sintab, X
    sta test_x0
    lda sintab+$100, X
    sta test_y0
    lda sintab, Y
    sta test_x1
    lda sintab+$100, Y
    sta test_y1
    cmd_fcn()
}

inline do_square(cmd_fcn)
{
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
    cmd_fcn()

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
    cmd_fcn()

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
    cmd_fcn()

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
    cmd_fcn()
}

/******************************************************************************/

word test_right_adjust_rom[2] = {-( (8*2*11) - 8), (8*2)}
byte pixel_pos_set_rom[8] = {$80,$40,$20,$10,$08,$04,$02,$01}
byte pixel_pos_clr_rom[8] = {$7F,$BF,$DF,$EF,$F7,$FB,$FD,$FE}

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
    bresenham_VPX(or_block, bcc, pixel_pos_set_rom, set_shift_right)
}
function bresenham_VPX_clr()
{
    bresenham_VPX(clr_block, bcs, pixel_pos_clr_rom, clr_shift_right)
}
function bresenham_VNX_set()
{
    bresenham_VNX(or_block, bcc, pixel_pos_set_rom, set_shift_left)
}
function bresenham_VNX_clr()
{
    bresenham_VNX(clr_block, bcs, pixel_pos_clr_rom, clr_shift_left)
}
function bresenham_HPY_set()
{
    bresenham_HPY(or_block, 0)
}
function bresenham_HPY_clr()
{
    bresenham_HPY(clr_block, 0xFF)
}
function bresenham_HNY_set()
{
    bresenham_HNY(or_block, 0)
}
function bresenham_HNY_clr()
{
    bresenham_HNY(clr_block, 0xFF)
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
}

inline bresenham_HNY(cmd_fcn, empty_row) {
    bresenham_H_common(cmd_fcn, empty_row, bresenham_up_fcn)
}

inline bresenham_HPY(cmd_fcn, empty_row) {
    bresenham_H_common(cmd_fcn, empty_row, bresenham_down_fcn)
}

inline clr_shift_right() {
    sec
    ror test_byte
}

inline set_shift_right() {
    lsr test_byte
}

inline clr_shift_left() {
    sec
    rol test_byte
}

inline set_shift_left() {
    asl test_byte
}

inline bresenham_down_fcn(cmd_fcn, empty_row) {
    // move down a line
    ldx test_y0
    inx
    stx test_y0

    // check if we're done with this block vertically
    txa
    and #7
    if (zero)
    {
        // is this block new already?
        lda cmd_lines
        if (not zero)
        {
            // send this block
            ldx test_block+0
            ldy test_block+1

            cmd_fcn()
        }

        // begin a new block
        lda test_y0
        and #7
        sta cmd_start
        tax
        lda #1
        sta cmd_lines

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
        inc cmd_lines
        tax
    }

    // start with an empty line
    lda #empty_row
    sta cmd_byte, X
}

inline bresenham_up_fcn(cmd_fcn, empty_row) {
    // move up a line
    ldx test_y0
    dex
    stx test_y0

    // check if we're done with this block vertically
    txa
    and #7
    cmp #7
    if (equal)
    {
        // is this block new already?
        lda cmd_lines
        if (not zero)
        {
            // send this block
            ldx test_block+0
            ldy test_block+1

            cmd_fcn()
        }

        // begin a new block
        lda test_y0
        and #7
        sta cmd_start
        tax
        lda #1
        sta cmd_lines

        // move to next block up
        sec
        lda test_block+0
        sbc #(12*8*2)
        sta test_block+0
        lda test_block+1
        sbc #0
        sta test_block+1
    }
    else
    {
        inc cmd_lines
        dec cmd_start
        tax
    }

    // start with an empty line
    lda #empty_row
    sta cmd_byte, X
}

inline bresenham_H_common(cmd_fcn, empty_row, updown_fcn) {
    bresenham_common_setup()

    // pixel position
    lda test_x0
    and #7
    tax
    lda pixel_pos_set_rom, X
    sta test_byte

    // begin a new block
    lda test_y0
    and #7
    sta cmd_start
    tax
    lda #1
    sta cmd_lines

    // start with an empty line
    lda #empty_row
    sta cmd_byte, X

    // do them columns
    forever {
        // plot!
        lda test_y0
        and #7
        tax
        lda test_byte
        eor cmd_byte, X
        sta cmd_byte, X

        lsr test_byte

        // check if we're done with this block horizontally
        if (carry)
        {
            // wrap pixel around
            ror test_byte

            // send it
            ldx test_block+0
            ldy test_block+1

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

            // begin a new block
            lda test_y0
            and #7
            sta cmd_start
            tax
            lda #1
            sta cmd_lines

            // start with an empty line
            lda #empty_row
            sta cmd_byte, X
        }
        else
        {
            dec test_iters
            if (equal) {
                // send whatever we did so far

                ldx test_block+0
                ldy test_block+1

                cmd_fcn()

                rts
            }
        }

        // go up/down as well?
        ldx #0
        bit test_err+1
        if (not minus)
        {
            updown_fcn(cmd_fcn, empty_row)

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

inline bresenham_VNX(cmd_fcn, wrap_check, pixel_pos_rom, shift_cmd) {
    bresenham_V_common(cmd_fcn, wrap_check, pixel_pos_rom, bresenham_left_fcn, shift_cmd, rol)
}

inline bresenham_VPX(cmd_fcn, wrap_check, pixel_pos_rom, shift_cmd) {
    bresenham_V_common(cmd_fcn, wrap_check, pixel_pos_rom, bresenham_right_fcn, shift_cmd, ror)
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

inline bresenham_V_common(cmd_fcn, wrap_check, pixel_pos_rom, rightleft_fcn, shift_cmd, rot_op) {
    bresenham_common_setup()

    // pixel position
    lda test_x0
    and #7
    tax
    lda pixel_pos_rom, X
    sta test_byte

    // begin a new block
    lda #0
    sta cmd_lines
    lda test_y0
    and #7
    sta cmd_start

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

        inc cmd_lines

        // check if we're done with this block vertically
        cpx #7
        if (equal)
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

            // begin a new block
            lda #0
            sta cmd_lines
            lda test_y0
            and #7
            sta cmd_start

            // move to next block down
            clc
            lda test_block+0
            and #~7
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
            shift_cmd
            wrap_check no_wrap
                // wrap pixel around
                rot_op test_byte

                // check if this isn't a new block
                lda cmd_lines
                if (not zero)
                {
                    // we had previously written to the current block

                    // send it
                    ldx test_block+0
                    ldy test_block+1

                    cmd_fcn()

                    // begin a new block
                    lda #0
                    sta cmd_lines
                    lda test_y0
                    and #7
                    sta cmd_start
                }

                rightleft_fcn()
no_wrap:

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
    do {
        ldy #32
        do {
            sta PPU.IO
            dey
        } while (not zero)
        dex
    } while (not zero)

    // perf bar scale
    vram_set_address_i( (NAME_TABLE_0_ADDRESS + (26*32) + 4) )
    ldy #12
    lda #0xFC
    do {
        vram_write_a()
        dey
    } while (not zero)

}

/******************************************************************************/

byte half_on_block[8] = {$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0}
byte on_block[8] = {$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF}

function init_patterns()
{
    // fixed patterns
    assign_16i(tmp_addr, half_on_block)
    vram_set_address_i( (TILES_WIDE * TILES_HIGH * 8 ) )
    ldx #2
    unpack_patterns()

    assign_16i(tmp_addr, half_on_block)
    vram_set_address_i( ( (TILES_WIDE * TILES_HIGH * 8) + 0x1000 ) )
    ldx #2
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
