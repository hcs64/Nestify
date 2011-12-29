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

#include "dlist.as"
#include "buffer.as"
#include "blocks.as"
#include "vector.as"

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

    /*
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
    */

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
    sta line_x0
    lda sintab+$100, X
    sta line_y0
    lda sintab, Y
    sta line_x1
    lda sintab+$100, Y
    sta line_y1
    bresenham_set()

    lda #$55
    tax
    clc
    adc #$55
    tay

    lda sintab, X
    //clc
    //adc #50
    sta line_x0
    lda sintab+$100, X
    sta line_y0
    lda sintab, Y
    sta line_x1
    lda sintab+$100, Y
    sta line_y1
    bresenham_set()

    lda #$aa
    tax
    clc
    adc #$56
    tay

    lda sintab, X
    sta line_x0
    lda sintab+$100, X
    sta line_y0
    lda sintab, Y
    sta line_x1
    lda sintab+$100, Y
    sta line_y1
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
    sta line_x0
    lda sintab+$100, X
    sta line_y0
    lda sintab, Y
    sta line_x1
    lda sintab+$100, Y
    sta line_y1
    cmd_fcn()

    lda #1
    clc
    adc #$55
    tax
    clc
    adc #$55
    tay

    lda sintab, X
    sta line_x0
    lda sintab+$100, X
    sta line_y0
    lda sintab, Y
    sta line_x1
    lda sintab+$100, Y
    sta line_y1
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
    sta line_x0
    lda sintab+$100, X
    sta line_y0
    lda sintab, Y
    sta line_x1
    lda sintab+$100, Y
    sta line_y1
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
    sta line_x0
    lda sintab+$100, X
    sta line_y0
    lda sintab, Y
    sta line_x1
    lda sintab+$100, Y
    sta line_y1
    cmd_fcn()

    lda test_angle
    clc
    adc #$40
    tax
    clc
    adc #$40
    tay

    lda sintab, X
    sta line_x0
    lda sintab+$100, X
    sta line_y0
    lda sintab, Y
    sta line_x1
    lda sintab+$100, Y
    sta line_y1
    cmd_fcn()

    lda test_angle
    clc
    adc #$80
    tax
    clc
    adc #$40
    tay

    lda sintab, X
    sta line_x0
    lda sintab+$100, X
    sta line_y0
    lda sintab, Y
    sta line_x1
    lda sintab+$100, Y
    sta line_y1
    cmd_fcn()

    lda test_angle
    clc
    adc #$C0
    tax
    clc
    adc #$40
    tay

    lda sintab, X
    sta line_x0
    lda sintab+$100, X
    sta line_y0
    lda sintab, Y
    sta line_x1
    lda sintab+$100, Y
    sta line_y1
    cmd_fcn()
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

    /*
    // perf bar scale
    vram_set_address_i( (NAME_TABLE_0_ADDRESS + (26*32) + 4) )
    ldy #12
    lda #0xFC
    do {
        vram_write_a()
        dey
    } while (not zero)
    */
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
