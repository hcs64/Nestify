#ines.mapper        "none"
#ines.mirroring     "Horizontal"
#ines.battery       "no"
#ines.trainer       "no"
#ines.fourscreen    "no"

#rom.banksize 32K

#include "nes.h"
#include "std.h"

#include "mem.as"

#rom.bank BANK_MAIN_ENTRY
#rom.org 0x8000

#include "newdlist.as"
#include "buffer.as"
#include "vector.as"

#interrupt.start    main
#interrupt.irq      int_irq
#interrupt.nmi      int_nmi

interrupt.irq int_irq()
{
}

interrupt.nmi int_nmi()
{
    pha // 3
    txa // 2
    pha // 3
    tya // 2
    pha // 3

    lda PPU.STATUS  // 4

    lda #1  // 2
    sta nmi_hit // 3

    sty rndy    // 3
    stx rndx    // 3
    ldy pal_cur
    set_palette()   // 6 + 60

    process_dlist() // 6+

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
    ldx #(stack_end-1)
    txs

    // clear the registers
    lda  #0

    sta  PPU.CNT0
    sta  PPU.CNT1

    sta  _ppu_ctl0
    sta  _ppu_ctl1

    sta  PPU.BG_SCROLL
    sta  PPU.BG_SCROLL

    sta  PCM_CNT
    sta  PCM_VOLUMECNT
    sta  SND_CNT

    lda  #0xC0
    sta  joystick.cnt1

    // clear ZP
    lda #0
    ldx #0
    do {
        sta 0x0, X
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
    init_dlist()
    lda #0
    sta cur_nametable_page

    // turn everything on
    vblank_wait()
    vram_clear_address()
    //ppu_ctl0_assign(#CR_NMI)
    ppu_ctl0_assign(#CR_NMI|CR_BACKADDR1000)
    //ppu_ctl1_assign(#CR_BACKVISIBLE|CR_SPRITESVISIBLE|CR_BACKNOCLIP|CR_SPRNOCLIP)
    ppu_ctl1_assign(#CR_BACKVISIBLE)

    // test begins

    mystify_test()
}

byte points_rom[] = {10,10,2,5, 160,100,-3,-7, 70,160,-6,-8, 100,35,2,-3}

function mystify_test()
{
    ldx #15
    do {
        lda points_rom, X
        sta points, X
        dex
    } while (not minus)

    lda #0
    sta head_poly
    sta tail_poly

    lda #$21
    sta pal_cur
    lda #$0
    sta pal_timer
    lda #$5
    sta pal_delay

    // draw initial polygons
    draw_poly()
    draw_poly()
    draw_poly()
    draw_poly()

    finish_frame()

    forever {
        clear_poly()
        draw_poly()

        change_palette()
        finish_frame()
    }
}

function change_palette()
{
    dec pal_timer
    bmi time_to_go
    rts
time_to_go:

    lda pal_delay
    sta pal_timer

    lda pal_dest
    cmp pal_cur
    if (equal)
    {
        lda rndx
        and #$3F
        sta pal_dest

        and #$F
        cmp #$C
        if (not minus)
        {
            lda pal_dest
            and #$37
            sta pal_dest
        }

        lda pal_dest
        and #$30
        if (zero)
        {
            lda pal_dest
            ora #$10
            sta pal_dest
        }

        lda rndy
        and #3
        clc
        adc #5
        sta pal_delay
    }

    lda pal_dest
    and #$F
    sta tmp_byte

    lda pal_cur
    and #$F
    cmp tmp_byte
    beq pal_hue_done
    bpl pal_hue_pl
    inc pal_cur
    bne pal_change_end
pal_hue_pl:
    dec pal_cur
    jmp pal_change_end

pal_hue_done:

    lda pal_dest
    and #$30
    sta tmp_byte

    lda pal_cur
    and #$30
    cmp tmp_byte
    beq pal_change_end
    bpl pal_value_pl
    clc
    lda pal_cur
    adc #$10
    sta pal_cur
    bne pal_change_end
pal_value_pl:
    sec
    lda pal_cur
    sbc #$10
    sta pal_cur

pal_change_end:
}

function draw_poly()
{
    ldx head_poly

    setup_poly_line(0)
    setup_poly_line(1)
    setup_poly_line(2)
    setup_poly_line(3)

    draw_poly_line(0)
    draw_poly_line(1)
    draw_poly_line(2)
    draw_poly_line(3)

    lda head_poly
    clc
    adc #sizeof(line_s)*NUM_POLYS
    and #POLY_WRAP_MASK
    sta head_poly

    update_poly_point(0)
    update_poly_point(1)
    update_poly_point(2)
    update_poly_point(3)
}

function clear_poly()
{
    clear_poly_line(0)
    clear_poly_line(1)
    clear_poly_line(2)
    clear_poly_line(3)

    lda tail_poly
    clc
    adc #sizeof(line_s)*NUM_POLYS
    and #POLY_WRAP_MASK
    sta tail_poly
}

inline setup_poly_line(num)
{
    lda points[num].x
    sta lines[(num-1)&3].x1, X
    sta lines[num].x0, X
    lda points[num].y
    sta lines[(num-1)&3].y1, X
    sta lines[num].y0, X
}

inline draw_poly_line(num)
{
    ldx head_poly

    lda lines[num].x0, X
    sta line_x0
    lda lines[num].y0, X
    sta line_y0
    lda lines[num].x1, X
    sta line_x1
    lda lines[num].y1, X
    sta line_y1

    bresenham_set()
}

inline clear_poly_line(num)
{
    ldx tail_poly

    lda lines[num].x0, X
    sta line_x0
    lda lines[num].y0, X
    sta line_y0
    lda lines[num].x1, X
    sta line_x1
    lda lines[num].y1, X
    sta line_y1

    bresenham_clr()
}

inline update_poly_point(num)
{
    clc
    lda points[num].vx
    if (minus)
    {
        adc points[num].x

        cmp points[num].x
        if (carry)
        {
            ldy #0
            beq flip_x
        }
    }
    else
    {
        adc points[num].x

        cmp #TILES_WIDE*8
        if (carry)
        {
            ldy #(TILES_WIDE*8)-1

flip_x:
            lda points[num].vx
            eor #0xFF
            tax
            inx
            stx points[num].vx

            tya
        }
    }
    sta points[num].x

    clc
    lda points[num].vy

    if (minus)
    {
        adc points[num].y

        cmp points[num].y
        if (carry)
        {
            ldy #0
            beq flip_y
        }
    }
    else
    {
        adc points[num].y

        cmp #TILES_HIGH*8
        if (carry)
        {
            ldy #(TILES_HIGH*8)-1

flip_y:
            lda points[num].vy
            eor #0xFF
            tax
            inx
            stx points[num].vy

            tya
        }
    }
    sta points[num].y
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
    ldy #$21
    set_palette()
    init_attrs()
    init_names()
}

// Y = fg color
// 60 cycles w/ rts
function set_palette()
{
    // Setup palette
    lda #hi(PAL_0_ADDRESS)
    sta PPU.ADDRESS
    lda #lo(PAL_0_ADDRESS)
    sta PPU.ADDRESS

    // palette 0
    ldx #0x0f   // bg
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
}
