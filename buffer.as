// mechanism for keeping track of double buffered tiles

#align 256
updaterangetab:
#incbin "updaterange.bin"

rangetab:
#incbin "rangetab.bin"

function init_tracktiles()
{
    // clear

    lda #0

    ldx #0
    do {
        inx
        sta tile_status, X
        sta tile_status+0x100, X
    } while (not zero)

    ldx #TILE_CACHE_ELEMENTS
    do {
        dex
        sta tile_cache, X
        sta tile_cache+0x40, X
        sta tile_cache+0x80, X
        sta tile_cache+0xC0, X
        sta tile_cache+0x100, X
        sta tile_cache+0x140, X
        sta tile_cache+0x180, X
        sta tile_cache+0x1C0, X
        sta tile_cache_dirty_range_0, X
        sta tile_cache_dirty_range_1, X
    } while (not zero)

    // init free list
    sta tile_cache_free_ptr
    ldx #TILE_CACHE_ELEMENTS-1
    do {
        txa
        dex
        sta tile_cache_list, X
    } while (not zero)
    lda #$FF
    sta tile_cache_list+TILE_CACHE_ELEMENTS-1

    lda #DIRTY_FRAME_0
    sta this_frame_mask
    lda #DIRTY_FRAME_1
    sta other_frame_mask
    lda #COUNT_MASK
    sta count_mask_zp

    lda #$FF
    sta tile_status_sentinel
}

inline tracktiles_finish_frame0(page, finish_label)
{
        // never need to update if this frame is clean
        bit this_frame_mask
        beq finish_label
        eor this_frame_mask
        sta tile_status+page, X

        stx tmp_byte2
        tay

        // prepare an address
        stx cmd_addr0
        lda #(page/0x100)
        asl cmd_addr0
        rol A
        asl cmd_addr0
        rol A
        asl cmd_addr0
        rol A
        ora cur_nametable_page
        sta cmd_addr1

        tya
        bit count_mask_zp
        if (zero)
        {
            cmd_tile_clear()
            jmp finish_finished0
        }
        
        cmd_tile_copy()

finish_finished0:
        ldx tmp_byte2
}

inline tracktiles_finish_frame_cached0(page, finish_label)
{
        and #CACHE_LINE_MASK
        tay

        lda tile_cache_list, Y
        sta tmp_byte

        stx tmp_byte2

        lda this_frame_mask
        cmp #DIRTY_FRAME_0
        if (equal)
        {
            ldx tile_cache_dirty_range_0, Y
            lda #0
            sta tile_cache_dirty_range_0, Y
        }
        else
        {
            ldx tile_cache_dirty_range_1, Y
            lda #0
            sta tile_cache_dirty_range_1, Y
        }

        // write only lines touched since this frame last updated

        txa
        // avoid doing anything if range is empty
        beq finish_finished_cached0

        // prepare an address
        lda tmp_byte2
        sta cmd_addr0
        lda #(page/0x100)
        asl cmd_addr0
        rol A
        asl cmd_addr0
        rol A
        asl cmd_addr0
        rol A
        ora cur_nametable_page
        sta cmd_addr1

        lda updaterangetab, X
        sta cmd_lines
        lda updaterangetab+0x100, X
        sta cmd_start

        sty cmd_cache_start

        cmd_tile_cache_write_lines()

finish_finished_cached0:
        ldx tmp_byte2
        jmp finish_label
}

finish_frame_p0_cache:
    tracktiles_finish_frame_cached0(0, finish_frame_check_p1)
    // unreachable

#align 256
function tracktiles_finish_frame()
{
    // update any stragglers from last frame, or cached dirties from this
    ldx #$FF

finish_frame_loop:
    inx

    lda tile_status, X

    beq finish_frame_check_p1
    bmi finish_frame_p0_cache

    tracktiles_finish_frame0(0, finish_frame_check_p1)

finish_frame_check_p1:
    lda tile_status+0x100, X
    beq finish_frame_loop
    bmi finish_frame_p1_cache

    tracktiles_finish_frame0(0x100, finish_frame_loop)
    jmp finish_frame_loop

finish_frame_p1_cache:
    cpx #$FF
    beq finish_frame_complete

    tracktiles_finish_frame_cached0(0x100, finish_frame_loop)
    // unreachable

finish_frame_complete:

    // swap masks
    lda this_frame_mask
    ldx other_frame_mask
    sta other_frame_mask
    stx this_frame_mask
}

// cmd_byte[X&7 to X&7 + cmd_lines] = bits to OR with
// Y:X = first line address
function noreturn or_block()
{
    stx cmd_addr0
    tya
    sta tmp_byte
    ora cur_nametable_page
    sta cmd_addr1

    txa
    lsr tmp_byte
    ror A
    lsr tmp_byte
    ror A
    lsr tmp_byte
    ror A
    tax
    lda tmp_byte

    beq add_prim_0
    jmp add_prim_100

add_prim_0:
    lda tile_status, X
    bmi add_cached_0
    add_prim(0)

add_cached_0:
    add_prim_cached(0)

add_prim_100:
    lda tile_status+0x100, X
    bmi add_cached_100
    add_prim(0x100)

add_cached_100:
    add_prim_cached(0x100)
}


inline add_prim_cached(page)
{
    // cached

    // not zero prims (implicitly)

    and #CACHE_LINE_MASK
    tax
    tay
    inc tile_cache_list, X
    lda tile_cache_list, X

    ora this_frame_mask
    sta tile_cache_list, X

    // mark changed lines dirty
    lda cmd_lines
    asl A
    asl A
    asl A
    ora cmd_start
    tax
    lda rangetab-8, X
    ora tile_cache_dirty_range_0, Y
    sta tile_cache_dirty_range_0, Y

    lda rangetab-8, X
    ora tile_cache_dirty_range_1, Y
    sta tile_cache_dirty_range_1, Y

    tile_cache_update_set()
    rts
}

inline add_prim(page)
{
    sta tmp_byte
    bit this_frame_mask
    bne add_copy

add_update:
    and #COUNT_MASK
    tay

    ora other_frame_mask
    sta tile_status+page, X
    inc tile_status+page, X

    tya
    if (zero)
    {
        ldy tile_cache_free_ptr
        bpl do_add_cache

        cmd_set_lines()

        rts
    }

    // not zero prims
    cmd_ora_lines()
    rts

add_copy:
    and #COUNT_MASK
    tay

    ora other_frame_mask
    sta tile_status+page, X
    inc tile_status+page, X

    tya
    if (zero)
    {
        ldy tile_cache_free_ptr
        bpl do_add_cache

        cmd_set_all_lines()

        rts
    }

    // not zero prims
    cmd_copy_ora_all_lines()
    rts

do_add_cache:
    lda #CACHED_MASK
    ora tile_cache_free_ptr
    sta tile_status+page, X

    // point free list head at next
    lda tile_cache_list, Y
    sta tile_cache_free_ptr

    // now use free list entry for count
    lda #1
    sta tile_cache_list, Y

    // set dirty range
    lda cmd_lines
    asl A
    asl A
    asl A
    ora cmd_start
    tax

    lda rangetab-8, X
    sta tile_cache_dirty_range_0, Y
    sta tile_cache_dirty_range_1, Y

    // if a frame was dirty we must consider its whole range dirty
    ldx #$FF
    lda tmp_byte
    and #DIRTY_FRAME_0
    if (not zero)
    {
        txa
        sta tile_cache_dirty_range_0, Y
    }

    lda tmp_byte
    and #DIRTY_FRAME_1
    if (not zero)
    {
        txa
        sta tile_cache_dirty_range_1, Y
    }

    tile_cache_update_set()

    rts
}

// cmd_byte[X&7 to X&7 + cmd_lines] = bits to clear
// Y:X = first line address
function noreturn clr_block()
{
    stx cmd_addr0
    tya
    sta tmp_byte
    ora cur_nametable_page
    sta cmd_addr1

    txa
    lsr tmp_byte
    ror A
    lsr tmp_byte
    ror A
    lsr tmp_byte
    ror A
    tax

    lda tmp_byte
    beq remove_prim_0
    jmp remove_prim_100

remove_prim_0:
    lda tile_status, X
    bmi remove_cached_0
    remove_prim(0)

remove_cached_0:
    remove_prim_cached(0)

remove_prim_100:
    lda tile_status+0x100, X
    bmi remove_cached_100
    remove_prim(0x100)

remove_cached_100:
    remove_prim_cached(0x100)
}

inline remove_prim_cached(page)
{
    stx tmp_byte

    and #CACHE_LINE_MASK
    tax
    ldy tile_cache_list, X
    dey
    sty tile_cache_list, X
    tya
    and #COUNT_MASK

    if (zero)
    {
        // update dirty range with current clear
        lda cmd_lines
        asl A
        asl A
        asl A
        ora cmd_start
        tay

        lda this_frame_mask
        cmp #DIRTY_FRAME_0

        if (equal)
        {
            lda tile_cache_dirty_range_0, X
        }
        else
        {
            lda tile_cache_dirty_range_1, X
        }

        ora rangetab-8, Y
        tay

        // clear active range
        lda updaterangetab, Y
        sta cmd_lines
        lda updaterangetab+0x100, Y
        sta cmd_start

        cmd_clr_lines()

        ldx tmp_byte
        lda tile_status+page, X
        and #CACHE_LINE_MASK
        tax

        // other frame will need to pick up this clear
        lda other_frame_mask
        ldy tmp_byte
        sta tile_status+page, Y

        // take it off the free list
        lda tile_cache_free_ptr
        sta tile_cache_list, X
        stx tile_cache_free_ptr

        ldy tile_cache_free_ptr

        lda #0
        sta tile_cache_dirty_range_0, Y
        sta tile_cache_dirty_range_1, Y

        tile_cache_remove_lines()

        rts
    }
    
    txa
    tay

    // mark updated lines
    lda cmd_lines
    asl A
    asl A
    asl A
    ora cmd_start
    tax
    lda rangetab-8, X
    ora tile_cache_dirty_range_0, Y
    sta tile_cache_dirty_range_0, Y

    lda rangetab-8, X
    ora tile_cache_dirty_range_1, Y
    sta tile_cache_dirty_range_1, Y

    tile_cache_update_clr()

    rts
}

inline remove_prim(page)
{
    sec
    sbc #1

    bit this_frame_mask
    bne remove_copy

remove_update:
    and #COUNT_MASK
    tay
    ora other_frame_mask
    sta tile_status+page, X

    tya
    if (zero)
    {
        cmd_clr_lines()

        rts
    }

    // not zero prims
    cmd_and_lines()
    rts

remove_copy:
    and #COUNT_MASK
    tay
    ora other_frame_mask
    sta tile_status+page, X

    tya
    if (zero)
    {
        cmd_tile_clear()

        rts
    }

    // not zero prims
    cmd_copy_and_all_lines()
    rts
}

// Y: cache line
function tile_cache_update_set()
{
    tya
    asl A
    asl A
    asl A
    ora cmd_start
    tay

    lda cmd_lines

    if (carry)
    {
        adc #7 // +1
    }

    tax

    lda tile_cache_update_set_jmptab_0, X
    sta tmp_addr+0
    lda tile_cache_update_set_jmptab_1, X
    sta tmp_addr+1

    ldx cmd_start

    jmp [tmp_addr]

tile_cache_update_set_8_lines:
    lda cmd_byte+7, X
    ora tile_cache+7, Y
    sta tile_cache+7, Y
tile_cache_update_set_7_lines:
    lda cmd_byte+6, X
    ora tile_cache+6, Y
    sta tile_cache+6, Y
tile_cache_update_set_6_lines:
    lda cmd_byte+5, X
    ora tile_cache+5, Y
    sta tile_cache+5, Y
tile_cache_update_set_5_lines:
    lda cmd_byte+4, X
    ora tile_cache+4, Y
    sta tile_cache+4, Y
tile_cache_update_set_4_lines:
    lda cmd_byte+3, X
    ora tile_cache+3, Y
    sta tile_cache+3, Y
tile_cache_update_set_3_lines:
    lda cmd_byte+2, X
    ora tile_cache+2, Y
    sta tile_cache+2, Y
tile_cache_update_set_2_lines:
    lda cmd_byte+1, X
    ora tile_cache+1, Y
    sta tile_cache+1, Y
tile_cache_update_set_1_lines:
    lda cmd_byte+0, X
    ora tile_cache+0, Y
    sta tile_cache+0, Y

    rts

tile_cache_update_set_8_lines1:
    lda cmd_byte+7, X
    ora tile_cache+0x107, Y
    sta tile_cache+0x107, Y
tile_cache_update_set_7_lines1:
    lda cmd_byte+6, X
    ora tile_cache+0x106, Y
    sta tile_cache+0x106, Y
tile_cache_update_set_6_lines1:
    lda cmd_byte+5, X
    ora tile_cache+0x105, Y
    sta tile_cache+0x105, Y
tile_cache_update_set_5_lines1:
    lda cmd_byte+4, X
    ora tile_cache+0x104, Y
    sta tile_cache+0x104, Y
tile_cache_update_set_4_lines1:
    lda cmd_byte+3, X
    ora tile_cache+0x103, Y
    sta tile_cache+0x103, Y
tile_cache_update_set_3_lines1:
    lda cmd_byte+2, X
    ora tile_cache+0x102, Y
    sta tile_cache+0x102, Y
tile_cache_update_set_2_lines1:
    lda cmd_byte+1, X
    ora tile_cache+0x101, Y
    sta tile_cache+0x101, Y
tile_cache_update_set_1_lines1:
    lda cmd_byte+0, X
    ora tile_cache+0x100, Y
    sta tile_cache+0x100, Y
}

byte tile_cache_update_set_jmptab_0[17] = {
    0,
    lo(tile_cache_update_set_1_lines),
    lo(tile_cache_update_set_2_lines),
    lo(tile_cache_update_set_3_lines),
    lo(tile_cache_update_set_4_lines),
    lo(tile_cache_update_set_5_lines),
    lo(tile_cache_update_set_6_lines),
    lo(tile_cache_update_set_7_lines),
    lo(tile_cache_update_set_8_lines),

    lo(tile_cache_update_set_1_lines1),
    lo(tile_cache_update_set_2_lines1),
    lo(tile_cache_update_set_3_lines1),
    lo(tile_cache_update_set_4_lines1),
    lo(tile_cache_update_set_5_lines1),
    lo(tile_cache_update_set_6_lines1),
    lo(tile_cache_update_set_7_lines1),
    lo(tile_cache_update_set_8_lines1),
}

byte tile_cache_update_set_jmptab_1[17] = {
    0,
    hi(tile_cache_update_set_1_lines),
    hi(tile_cache_update_set_2_lines),
    hi(tile_cache_update_set_3_lines),
    hi(tile_cache_update_set_4_lines),
    hi(tile_cache_update_set_5_lines),
    hi(tile_cache_update_set_6_lines),
    hi(tile_cache_update_set_7_lines),
    hi(tile_cache_update_set_8_lines),

    hi(tile_cache_update_set_1_lines1),
    hi(tile_cache_update_set_2_lines1),
    hi(tile_cache_update_set_3_lines1),
    hi(tile_cache_update_set_4_lines1),
    hi(tile_cache_update_set_5_lines1),
    hi(tile_cache_update_set_6_lines1),
    hi(tile_cache_update_set_7_lines1),
    hi(tile_cache_update_set_8_lines1),
}

// Y: cache line
function tile_cache_update_clr()
{
    tya
    asl A
    asl A
    asl A
    ora cmd_start
    tay

    lda cmd_lines

    if (carry)
    {
        adc #7 // +1
    }

    tax

    lda tile_cache_update_clr_jmptab_0, X
    sta tmp_addr+0
    lda tile_cache_update_clr_jmptab_1, X
    sta tmp_addr+1

    ldx cmd_start

    jmp [tmp_addr]

tile_cache_update_clr_8_lines:
    lda cmd_byte+7, X
    and tile_cache+7, Y
    sta tile_cache+7, Y
tile_cache_update_clr_7_lines:
    lda cmd_byte+6, X
    and tile_cache+6, Y
    sta tile_cache+6, Y
tile_cache_update_clr_6_lines:
    lda cmd_byte+5, X
    and tile_cache+5, Y
    sta tile_cache+5, Y
tile_cache_update_clr_5_lines:
    lda cmd_byte+4, X
    and tile_cache+4, Y
    sta tile_cache+4, Y
tile_cache_update_clr_4_lines:
    lda cmd_byte+3, X
    and tile_cache+3, Y
    sta tile_cache+3, Y
tile_cache_update_clr_3_lines:
    lda cmd_byte+2, X
    and tile_cache+2, Y
    sta tile_cache+2, Y
tile_cache_update_clr_2_lines:
    lda cmd_byte+1, X
    and tile_cache+1, Y
    sta tile_cache+1, Y
tile_cache_update_clr_1_lines:
    lda cmd_byte+0, X
    and tile_cache+0, Y
    sta tile_cache+0, Y

    rts

tile_cache_update_clr_8_lines1:
    lda cmd_byte+7, X
    and tile_cache+0x107, Y
    sta tile_cache+0x107, Y
tile_cache_update_clr_7_lines1:
    lda cmd_byte+6, X
    and tile_cache+0x106, Y
    sta tile_cache+0x106, Y
tile_cache_update_clr_6_lines1:
    lda cmd_byte+5, X
    and tile_cache+0x105, Y
    sta tile_cache+0x105, Y
tile_cache_update_clr_5_lines1:
    lda cmd_byte+4, X
    and tile_cache+0x104, Y
    sta tile_cache+0x104, Y
tile_cache_update_clr_4_lines1:
    lda cmd_byte+3, X
    and tile_cache+0x103, Y
    sta tile_cache+0x103, Y
tile_cache_update_clr_3_lines1:
    lda cmd_byte+2, X
    and tile_cache+0x102, Y
    sta tile_cache+0x102, Y
tile_cache_update_clr_2_lines1:
    lda cmd_byte+1, X
    and tile_cache+0x101, Y
    sta tile_cache+0x101, Y
tile_cache_update_clr_1_lines1:
    lda cmd_byte+0, X
    and tile_cache+0x100, Y
    sta tile_cache+0x100, Y
}

byte tile_cache_update_clr_jmptab_0[17] = {
    0,
    lo(tile_cache_update_clr_1_lines),
    lo(tile_cache_update_clr_2_lines),
    lo(tile_cache_update_clr_3_lines),
    lo(tile_cache_update_clr_4_lines),
    lo(tile_cache_update_clr_5_lines),
    lo(tile_cache_update_clr_6_lines),
    lo(tile_cache_update_clr_7_lines),
    lo(tile_cache_update_clr_8_lines),

    lo(tile_cache_update_clr_1_lines1),
    lo(tile_cache_update_clr_2_lines1),
    lo(tile_cache_update_clr_3_lines1),
    lo(tile_cache_update_clr_4_lines1),
    lo(tile_cache_update_clr_5_lines1),
    lo(tile_cache_update_clr_6_lines1),
    lo(tile_cache_update_clr_7_lines1),
    lo(tile_cache_update_clr_8_lines1),
}

byte tile_cache_update_clr_jmptab_1[17] = {
    0,
    hi(tile_cache_update_clr_1_lines),
    hi(tile_cache_update_clr_2_lines),
    hi(tile_cache_update_clr_3_lines),
    hi(tile_cache_update_clr_4_lines),
    hi(tile_cache_update_clr_5_lines),
    hi(tile_cache_update_clr_6_lines),
    hi(tile_cache_update_clr_7_lines),
    hi(tile_cache_update_clr_8_lines),

    hi(tile_cache_update_clr_1_lines1),
    hi(tile_cache_update_clr_2_lines1),
    hi(tile_cache_update_clr_3_lines1),
    hi(tile_cache_update_clr_4_lines1),
    hi(tile_cache_update_clr_5_lines1),
    hi(tile_cache_update_clr_6_lines1),
    hi(tile_cache_update_clr_7_lines1),
    hi(tile_cache_update_clr_8_lines1),
}

// Y: cache line
function tile_cache_remove()
{
    tya
    asl A
    asl A
    asl A
    tay

    lda #0

    bcs tile_cache_remove_8_lines1

tile_cache_remove_8_lines:
    sta tile_cache+7, Y
tile_cache_remove_7_lines:
    sta tile_cache+6, Y
tile_cache_remove_6_lines:
    sta tile_cache+5, Y
tile_cache_remove_5_lines:
    sta tile_cache+4, Y
tile_cache_remove_4_lines:
    sta tile_cache+3, Y
tile_cache_remove_3_lines:
    sta tile_cache+2, Y
tile_cache_remove_2_lines:
    sta tile_cache+1, Y
tile_cache_remove_1_lines:
    sta tile_cache+0, Y

    rts

tile_cache_remove_8_lines1:
    sta tile_cache+0x107, Y
tile_cache_remove_7_lines1:
    sta tile_cache+0x106, Y
tile_cache_remove_6_lines1:
    sta tile_cache+0x105, Y
tile_cache_remove_5_lines1:
    sta tile_cache+0x104, Y
tile_cache_remove_4_lines1:
    sta tile_cache+0x103, Y
tile_cache_remove_3_lines1:
    sta tile_cache+0x102, Y
tile_cache_remove_2_lines1:
    sta tile_cache+0x101, Y
tile_cache_remove_1_lines1:
    sta tile_cache+0x100, Y

}

// Y: cache line
function noreturn tile_cache_remove_lines()
{
    tya
    asl A
    asl A
    asl A
    ora cmd_start
    tay

    lda cmd_lines

    if (carry)
    {
        adc #7 // +1
    }

    tax

    lda tile_cache_remove_lines_jmptab_0, X
    sta tmp_addr+0
    lda tile_cache_remove_lines_jmptab_1, X
    sta tmp_addr+1

    ldx cmd_start
    lda #0

    jmp [tmp_addr]
}

byte tile_cache_remove_lines_jmptab_0[17] = {
    0,
    lo(tile_cache_remove_1_lines),
    lo(tile_cache_remove_2_lines),
    lo(tile_cache_remove_3_lines),
    lo(tile_cache_remove_4_lines),
    lo(tile_cache_remove_5_lines),
    lo(tile_cache_remove_6_lines),
    lo(tile_cache_remove_7_lines),
    lo(tile_cache_remove_8_lines),

    lo(tile_cache_remove_1_lines1),
    lo(tile_cache_remove_2_lines1),
    lo(tile_cache_remove_3_lines1),
    lo(tile_cache_remove_4_lines1),
    lo(tile_cache_remove_5_lines1),
    lo(tile_cache_remove_6_lines1),
    lo(tile_cache_remove_7_lines1),
    lo(tile_cache_remove_8_lines1),
}

byte tile_cache_remove_lines_jmptab_1[17] = {
    0,
    hi(tile_cache_remove_1_lines),
    hi(tile_cache_remove_2_lines),
    hi(tile_cache_remove_3_lines),
    hi(tile_cache_remove_4_lines),
    hi(tile_cache_remove_5_lines),
    hi(tile_cache_remove_6_lines),
    hi(tile_cache_remove_7_lines),
    hi(tile_cache_remove_8_lines),

    hi(tile_cache_remove_1_lines1),
    hi(tile_cache_remove_2_lines1),
    hi(tile_cache_remove_3_lines1),
    hi(tile_cache_remove_4_lines1),
    hi(tile_cache_remove_5_lines1),
    hi(tile_cache_remove_6_lines1),
    hi(tile_cache_remove_7_lines1),
    hi(tile_cache_remove_8_lines1),
}

