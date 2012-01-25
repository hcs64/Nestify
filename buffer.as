// mechanism for keeping track of double buffered tiles

function init_tracktiles()
{
    // clear

    ldx #0
    lda #0

    do {
        inx
        sta tile_status, X
    } while (not zero)

    ldx #(TILES_WIDE*TILES_HIGH)-0x100
    do {
        dex
        sta tile_status+0x100, X
    } while (not zero)

    ldx #TILE_CACHE_ELEMENTS
    do {
        dex
        sta tile_cache_0, X
        sta tile_cache_1, X
        sta tile_cache_2, X
        sta tile_cache_3, X
        sta tile_cache_4, X
        sta tile_cache_5, X
        sta tile_cache_6, X
        sta tile_cache_7, X
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
}

inline tracktiles_finish_frame0(count, page)
{
    ldx #count
    do {
        dex

        lda tile_status+page, X

        beq no_finish_needed

        bmi finish_cache

        // never need to update if it wasn't touched previous frame
        bit other_frame_mask
        beq no_finish_needed

        eor other_frame_mask
        sta tile_status+page, X

        // never need to update if it was touched already this frame
        bit this_frame_mask
        bne no_finish_needed

        stx tmp_byte2
        tay

        // prepare an address
        stx cmd_addr+0
        lda #(page/0x100)
        asl cmd_addr+0
        rol A
        asl cmd_addr+0
        rol A
        asl cmd_addr+0
        rol A
        ora cur_nametable_page
        sta cmd_addr+1

        tya
        bit count_mask_zp
        if (zero)
        {
            cmd_tile_clear()
            jmp finish_finished
        }
        
        cmd_tile_copy()
        jmp finish_finished

finish_cache:
        and #CACHE_LINE_MASK
        tay
        lda tile_cache_list, Y

        // never need to update if it wasn't touched previous frame
        bit other_frame_mask
        beq no_finish_needed

        eor other_frame_mask
        sta tile_cache_list, Y

        // never need to update if it was touched already this frame
        bit this_frame_mask
        bne no_finish_needed

        stx tmp_byte2

        // prepare an address
        stx cmd_addr+0
        lda #(page/0x100)
        asl cmd_addr+0
        rol A
        asl cmd_addr+0
        rol A
        asl cmd_addr+0
        rol A
        ora cur_nametable_page
        sta cmd_addr+1

        sty cmd_cache_start
        cmd_tile_cache_write()

finish_finished:
        ldx tmp_byte2

no_finish_needed:

        cpx #0
    } while (not equal)
}

function tracktiles_finish_frame()
{
    // update any stragglers from last frame, or cached dirties from this
    tracktiles_finish_frame0(0,0)
    tracktiles_finish_frame0( (TILES_WIDE*TILES_HIGH)-0x100, 0x100)

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

    bit this_frame_mask
    bne add_cached_update
    ora this_frame_mask
    sta tile_cache_list, X

    bit other_frame_mask
    bne add_cached_copy

add_cached_update:
    tile_cache_update_set()

    // write back only the changed lines
    cmd_set_lines()
    rts

add_cached_copy:
    stx cmd_cache_start

    tile_cache_update_set()

    // write the whole block
    cmd_tile_cache_write()
    rts
}

inline add_prim(page)
{
    bit this_frame_mask
    bne add_update
    ora this_frame_mask

    bit other_frame_mask
    bne add_copy

add_update:
    // TF || !OF
    sta tile_status+page, X
    inc tile_status+page, X

    bit count_mask_zp
    if (zero)
    {
        stx tmp_byte    // unmolested by cmd_set_lines

        cmd_set_lines()

        ldx tmp_byte

        jmp try_add_cache
    }

    // not zero prims
    cmd_ora_lines()
    rts

add_copy:
    // !TF && OF
    sta tile_status+page, X
    inc tile_status+page, X

    bit count_mask_zp
    if (zero)
    {
        stx tmp_byte

        cmd_set_all_lines()

        ldx tmp_byte

try_add_cache:
        ldy tile_cache_free_ptr
        if (not minus)
        {
            lda tile_status+page, X
            sta tmp_byte
            lda #CACHED_MASK
            ora tile_cache_free_ptr
            sta tile_status+page, X

            // point free list head at next
            lda tile_cache_list, Y
            sta tile_cache_free_ptr

            // now use free list entry for status
            lda tmp_byte
            and #(DIRTY_FRAME_0|DIRTY_FRAME_1)
            ora #1
            sta tile_cache_list, Y

            tile_cache_add_lines()
        }
        rts
    }

    // not zero prims
    cmd_copy_ora_all_lines()
    rts
}

// cmd_byte[X&7 to X&7 + cmd_lines] = bits to clear
// Y:X = first line address
function noreturn clr_block()
{
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
    lda tile_cache_list, X

    bit this_frame_mask
    bne remove_cached_update
    ora this_frame_mask
    sta tile_cache_list, X

    bit other_frame_mask
    bne remove_cached_copy

remove_cached_update:

    ldy tile_cache_list, X
    dey
    sty tile_cache_list, X
    tya
    and #COUNT_MASK

    if (zero)
    {
        cmd_clr_lines()

evict_from_cache:
        ldx tmp_byte
        lda tile_status+page, X
        and #CACHE_LINE_MASK
        tax

        // take it off the free list
        lda tile_cache_list, X
        and #(DIRTY_FRAME_0|DIRTY_FRAME_1)
        ldy tmp_byte
        sta tile_status+page, Y

        lda tile_cache_free_ptr
        sta tile_cache_list, X
        stx tile_cache_free_ptr

        ldy tile_cache_free_ptr

        tile_cache_remove_lines()

        rts
    }
    
    txa
    tay
    tile_cache_update_clr()

    cmd_set_lines()

    rts

remove_cached_copy:

    ldy tile_cache_list, X
    dey
    sty tile_cache_list, X
    tya
    and #COUNT_MASK

    if (zero)
    {
        cmd_tile_clear()

        jmp evict_from_cache
    }

    txa
    tay
    sty cmd_cache_start

    tile_cache_update_clr()

    cmd_tile_cache_write()

    rts

}

inline remove_prim(page)
{
    sec
    sbc #1

    bit this_frame_mask
    bne remove_update
    ora this_frame_mask

    bit other_frame_mask
    bne remove_copy

remove_update:
    // TF || !OF
    sta tile_status+page, X

    bit count_mask_zp
    if (zero)
    {
        cmd_clr_lines()

        rts
    }

    // not zero prims
    cmd_and_lines()
    rts

remove_copy:
    // !TF && OF
    sta tile_status+page, X

    bit count_mask_zp
    if (zero)
    {
        cmd_tile_clear()

        rts
    }

    // not zero prims
    cmd_copy_and_all_lines()
    rts
}

inline setup_cache_line_addr()
{
    lda tile_cache_tab_0, X
    sta tmp_addr+0
    lda tile_cache_tab_1, X
    sta tmp_addr+1
}

// writes back into cmd_byte for easier update
// Y: cache line
function tile_cache_update_set()
{
    ldx cmd_lines
    lda tile_cache_update_set_jmptab_0, X
    sta tmp_addr+0
    lda tile_cache_update_set_jmptab_1, X
    sta tmp_addr+1

    ldx cmd_start

    jmp [tmp_addr]

tile_cache_update_set_8_lines:
    lda cmd_byte+0
    ora tile_cache_0, Y
    sta tile_cache_0, Y
    sta cmd_byte+0

    lda cmd_byte+1
    ora tile_cache_1, Y
    sta tile_cache_1, Y
    sta cmd_byte+1

    lda cmd_byte+2
    ora tile_cache_2, Y
    sta tile_cache_2, Y
    sta cmd_byte+2

    lda cmd_byte+3
    ora tile_cache_3, Y
    sta tile_cache_3, Y
    sta cmd_byte+3

    lda cmd_byte+4
    ora tile_cache_4, Y
    sta tile_cache_4, Y
    sta cmd_byte+4

    lda cmd_byte+5
    ora tile_cache_5, Y
    sta tile_cache_5, Y
    sta cmd_byte+5

    lda cmd_byte+6
    ora tile_cache_6, Y
    sta tile_cache_6, Y
    sta cmd_byte+6

    lda cmd_byte+7
    ora tile_cache_7, Y
    sta tile_cache_7, Y
    sta cmd_byte+7

    rts

tile_cache_update_set_7_lines:
    setup_cache_line_addr()
    lda cmd_byte, X
    ora [tmp_addr], Y
    sta [tmp_addr], Y
    sta cmd_byte, X
    inx
tile_cache_update_set_6_lines:
    setup_cache_line_addr()
    lda cmd_byte, X
    ora [tmp_addr], Y
    sta [tmp_addr], Y
    sta cmd_byte, X
    inx
tile_cache_update_set_5_lines:
    setup_cache_line_addr()
    lda cmd_byte, X
    ora [tmp_addr], Y
    sta [tmp_addr], Y
    sta cmd_byte, X
    inx
tile_cache_update_set_4_lines:
    setup_cache_line_addr()
    lda cmd_byte, X
    ora [tmp_addr], Y
    sta [tmp_addr], Y
    sta cmd_byte, X
    inx
tile_cache_update_set_3_lines:
    setup_cache_line_addr()
    lda cmd_byte, X
    ora [tmp_addr], Y
    sta [tmp_addr], Y
    sta cmd_byte, X
    inx
tile_cache_update_set_2_lines:
    setup_cache_line_addr()
    lda cmd_byte, X
    ora [tmp_addr], Y
    sta [tmp_addr], Y
    sta cmd_byte, X
    inx
tile_cache_update_set_1_lines:
    setup_cache_line_addr()
    lda cmd_byte, X
    ora [tmp_addr], Y
    sta [tmp_addr], Y
    sta cmd_byte, X
}

byte tile_cache_update_set_jmptab_0[9] = {
    0,
    lo(tile_cache_update_set_1_lines),
    lo(tile_cache_update_set_2_lines),
    lo(tile_cache_update_set_3_lines),
    lo(tile_cache_update_set_4_lines),
    lo(tile_cache_update_set_5_lines),
    lo(tile_cache_update_set_6_lines),
    lo(tile_cache_update_set_7_lines),
    lo(tile_cache_update_set_8_lines),
}

byte tile_cache_update_set_jmptab_1[9] = {
    0,
    hi(tile_cache_update_set_1_lines),
    hi(tile_cache_update_set_2_lines),
    hi(tile_cache_update_set_3_lines),
    hi(tile_cache_update_set_4_lines),
    hi(tile_cache_update_set_5_lines),
    hi(tile_cache_update_set_6_lines),
    hi(tile_cache_update_set_7_lines),
    hi(tile_cache_update_set_8_lines),
}

// writes back into cmd_byte for easier update
// Y: cache line
function tile_cache_update_clr()
{
    ldx cmd_lines
    lda tile_cache_update_clr_jmptab_0, X
    sta tmp_addr+0
    lda tile_cache_update_clr_jmptab_1, X
    sta tmp_addr+1

    ldx cmd_start

    jmp [tmp_addr]

tile_cache_update_clr_8_lines:
    lda cmd_byte+0
    and tile_cache_0, Y
    sta tile_cache_0, Y
    sta cmd_byte+0

    lda cmd_byte+1
    and tile_cache_1, Y
    sta tile_cache_1, Y
    sta cmd_byte+1

    lda cmd_byte+2
    and tile_cache_2, Y
    sta tile_cache_2, Y
    sta cmd_byte+2

    lda cmd_byte+3
    and tile_cache_3, Y
    sta tile_cache_3, Y
    sta cmd_byte+3

    lda cmd_byte+4
    and tile_cache_4, Y
    sta tile_cache_4, Y
    sta cmd_byte+4

    lda cmd_byte+5
    and tile_cache_5, Y
    sta tile_cache_5, Y
    sta cmd_byte+5

    lda cmd_byte+6
    and tile_cache_6, Y
    sta tile_cache_6, Y
    sta cmd_byte+6

    lda cmd_byte+7
    and tile_cache_7, Y
    sta tile_cache_7, Y
    sta cmd_byte+7


    rts

tile_cache_update_clr_7_lines:
    setup_cache_line_addr()
    lda cmd_byte, X
    and [tmp_addr], Y
    sta [tmp_addr], Y
    sta cmd_byte, X
    inx
tile_cache_update_clr_6_lines:
    setup_cache_line_addr()
    lda cmd_byte, X
    and [tmp_addr], Y
    sta [tmp_addr], Y
    sta cmd_byte, X
    inx
tile_cache_update_clr_5_lines:
    setup_cache_line_addr()
    lda cmd_byte, X
    and [tmp_addr], Y
    sta [tmp_addr], Y
    sta cmd_byte, X
    inx
tile_cache_update_clr_4_lines:
    setup_cache_line_addr()
    lda cmd_byte, X
    and [tmp_addr], Y
    sta [tmp_addr], Y
    sta cmd_byte, X
    inx
tile_cache_update_clr_3_lines:
    setup_cache_line_addr()
    lda cmd_byte, X
    and [tmp_addr], Y
    sta [tmp_addr], Y
    sta cmd_byte, X
    inx
tile_cache_update_clr_2_lines:
    setup_cache_line_addr()
    lda cmd_byte, X
    and [tmp_addr], Y
    sta [tmp_addr], Y
    sta cmd_byte, X
    inx
tile_cache_update_clr_1_lines:
    setup_cache_line_addr()
    lda cmd_byte, X
    and [tmp_addr], Y
    sta [tmp_addr], Y
    sta cmd_byte, X
}

byte tile_cache_update_clr_jmptab_0[9] = {
    0,
    lo(tile_cache_update_clr_1_lines),
    lo(tile_cache_update_clr_2_lines),
    lo(tile_cache_update_clr_3_lines),
    lo(tile_cache_update_clr_4_lines),
    lo(tile_cache_update_clr_5_lines),
    lo(tile_cache_update_clr_6_lines),
    lo(tile_cache_update_clr_7_lines),
    lo(tile_cache_update_clr_8_lines),
}

byte tile_cache_update_clr_jmptab_1[9] = {
    0,
    hi(tile_cache_update_clr_1_lines),
    hi(tile_cache_update_clr_2_lines),
    hi(tile_cache_update_clr_3_lines),
    hi(tile_cache_update_clr_4_lines),
    hi(tile_cache_update_clr_5_lines),
    hi(tile_cache_update_clr_6_lines),
    hi(tile_cache_update_clr_7_lines),
    hi(tile_cache_update_clr_8_lines),
}

// Y: cache line
function tile_cache_add_lines()
{
    ldx cmd_lines
    lda tile_cache_add_lines_jmptab_0, X
    sta tmp_addr+0
    lda tile_cache_add_lines_jmptab_1, X
    sta tmp_addr+1

    ldx cmd_start

    jmp [tmp_addr]

tile_cache_add_8_lines:
    lda cmd_byte+0
    sta tile_cache_0, Y
    lda cmd_byte+1
    sta tile_cache_1, Y
    lda cmd_byte+2
    sta tile_cache_2, Y
    lda cmd_byte+3
    sta tile_cache_3, Y
    lda cmd_byte+4
    sta tile_cache_4, Y
    lda cmd_byte+5
    sta tile_cache_5, Y
    lda cmd_byte+6
    sta tile_cache_6, Y
    lda cmd_byte+7
    sta tile_cache_7, Y
    rts

tile_cache_add_7_lines:
    setup_cache_line_addr()
    lda cmd_byte, X
    sta [tmp_addr], Y
    inx
tile_cache_add_6_lines:
    setup_cache_line_addr()
    lda cmd_byte, X
    sta [tmp_addr], Y
    inx
tile_cache_add_5_lines:
    setup_cache_line_addr()
    lda cmd_byte, X
    sta [tmp_addr], Y
    inx
tile_cache_add_4_lines:
    setup_cache_line_addr()
    lda cmd_byte, X
    sta [tmp_addr], Y
    inx
tile_cache_add_3_lines:
    setup_cache_line_addr()
    lda cmd_byte, X
    sta [tmp_addr], Y
    inx
tile_cache_add_2_lines:
    setup_cache_line_addr()
    lda cmd_byte, X
    sta [tmp_addr], Y
    inx
tile_cache_add_1_lines:
    setup_cache_line_addr()
    lda cmd_byte, X
    sta [tmp_addr], Y
}

byte tile_cache_add_lines_jmptab_0[9] = {
    0,
    lo(tile_cache_add_1_lines),
    lo(tile_cache_add_2_lines),
    lo(tile_cache_add_3_lines),
    lo(tile_cache_add_4_lines),
    lo(tile_cache_add_5_lines),
    lo(tile_cache_add_6_lines),
    lo(tile_cache_add_7_lines),
    lo(tile_cache_add_8_lines),
}

byte tile_cache_add_lines_jmptab_1[9] = {
    0,
    hi(tile_cache_add_1_lines),
    hi(tile_cache_add_2_lines),
    hi(tile_cache_add_3_lines),
    hi(tile_cache_add_4_lines),
    hi(tile_cache_add_5_lines),
    hi(tile_cache_add_6_lines),
    hi(tile_cache_add_7_lines),
    hi(tile_cache_add_8_lines),
}

// Y: cache line
function tile_cache_remove()
{
    lda #0

    sta tile_cache_0, Y
    sta tile_cache_1, Y
    sta tile_cache_2, Y
    sta tile_cache_3, Y
    sta tile_cache_4, Y
    sta tile_cache_5, Y
    sta tile_cache_6, Y
    sta tile_cache_7, Y
}

// Y: cache line
function tile_cache_remove_lines()
{
    ldx cmd_lines
    lda tile_cache_remove_lines_jmptab_0, X
    sta tmp_addr+0
    lda tile_cache_remove_lines_jmptab_1, X
    sta tmp_addr+1

    ldx cmd_start

    jmp [tmp_addr]

tile_cache_remove_7_lines:
    setup_cache_line_addr()
    lda #0
    sta [tmp_addr], Y
    inx
tile_cache_remove_6_lines:
    setup_cache_line_addr()
    lda #0
    sta [tmp_addr], Y
    inx
tile_cache_remove_5_lines:
    setup_cache_line_addr()
    lda #0
    sta [tmp_addr], Y
    inx
tile_cache_remove_4_lines:
    setup_cache_line_addr()
    lda #0
    sta [tmp_addr], Y
    inx
tile_cache_remove_3_lines:
    setup_cache_line_addr()
    lda #0
    sta [tmp_addr], Y
    inx
tile_cache_remove_2_lines:
    setup_cache_line_addr()
    lda #0
    sta [tmp_addr], Y
    inx
tile_cache_remove_1_lines:
    setup_cache_line_addr()
    lda #0
    sta [tmp_addr], Y
}

byte tile_cache_remove_lines_jmptab_0[9] = {
    0,
    lo(tile_cache_remove_1_lines),
    lo(tile_cache_remove_2_lines),
    lo(tile_cache_remove_3_lines),
    lo(tile_cache_remove_4_lines),
    lo(tile_cache_remove_5_lines),
    lo(tile_cache_remove_6_lines),
    lo(tile_cache_remove_7_lines),
    lo(tile_cache_remove),
}

byte tile_cache_remove_lines_jmptab_1[9] = {
    0,
    hi(tile_cache_remove_1_lines),
    hi(tile_cache_remove_2_lines),
    hi(tile_cache_remove_3_lines),
    hi(tile_cache_remove_4_lines),
    hi(tile_cache_remove_5_lines),
    hi(tile_cache_remove_6_lines),
    hi(tile_cache_remove_7_lines),
    hi(tile_cache_remove),
}

#align 256
byte tile_cache_tab_0[8] = {
    lo(tile_cache_0),
    lo(tile_cache_1),
    lo(tile_cache_2),
    lo(tile_cache_3),
    lo(tile_cache_4),
    lo(tile_cache_5),
    lo(tile_cache_6),
    lo(tile_cache_7),
}

byte tile_cache_tab_1[8] = {
    hi(tile_cache_0),
    hi(tile_cache_1),
    hi(tile_cache_2),
    hi(tile_cache_3),
    hi(tile_cache_4),
    hi(tile_cache_5),
    hi(tile_cache_6),
    hi(tile_cache_7),
}

