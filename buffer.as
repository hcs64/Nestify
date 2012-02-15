// mechanism for keeping track of double buffered tiles

#align 256
updaterangetab:
#incbin "updaterange.bin"

rangetab:
#incbin "rangetab.bin"

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
}

inline tracktiles_finish_frame0(count, page)
{
    ldx #count

finish_loop:
        dex

        lda tile_status+page, X

        beq no_finish_halfway

        bmi finish_cache

        // clear tile (no-preseve mode)
        tay
        and #TILE_USED_MASK

        if (not equal)
        {
            // there is something to erase 2 frames from now
            tya
            and #~TILE_USED_MASK
            ora this_frame_mask
            sta tile_status+page,X
            jmp no_finish_halfway
        }

        // never need to update if this frame is clean
        tya
        bit this_frame_mask
        beq no_finish_halfway

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

        cmd_tile_clear()
        jmp finish_finished

no_finish_halfway:
        cpx #0
        bne finish_loop
        jmp finish_loop_end

finish_cache:

        and #CACHE_LINE_MASK
        tay

        lda tile_cache_list, Y

        stx tmp_byte2

        lda this_frame_mask
        cmp #DIRTY_FRAME_0
        if (equal)
        {
            ldx tile_cache_dirty_range_0, Y
        }
        else
        {
            ldx tile_cache_dirty_range_1, Y
        }

        // write only lines touched this frame

        txa
no_dirty_lines:
        beq no_dirty_lines

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

        // evict from cache (no-preserve mode)
        ldy tmp_byte2
        lda tile_status+page, Y
        and #CACHE_LINE_MASK
        tax

        // 2 frames from now we will need to clear this
        lda tile_cache_list, X
        and other_frame_mask
        ora this_frame_mask
        sta tile_status+page, Y

        // take it off the free list
        lda tile_cache_free_ptr
        sta tile_cache_list, X
        stx tile_cache_free_ptr

        ldy tile_cache_free_ptr

        lda #0
        sta tile_cache_dirty_range_0, Y
        sta tile_cache_dirty_range_1, Y

finish_finished:
        ldx tmp_byte2

no_finish_needed:

        cpx #0
    beq finish_loop_end
    jmp finish_loop

finish_loop_end:
    nop
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
    lda tile_cache_list, X
    ora #TILE_USED_MASK
    sta tile_cache_list, X

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

    jsr tile_cache_update_set
    rts
}

inline add_prim(page)
{
    sta tmp_byte
    bit this_frame_mask
    bne add_copy

add_update:
    tay
    ora #TILE_USED_MASK
    sta tile_status+page, X

    tya
    and #TILE_USED_MASK
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
    tay
    eor this_frame_mask
    ora #TILE_USED_MASK
    sta tile_status+page, X

    tya
    and #TILE_USED_MASK
    if (zero)
    {
        ldy tile_cache_free_ptr
        bpl do_add_cache

        cmd_set_all_lines()

        rts
    }

    // not zero prims
    forever{}
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
    lda tmp_byte
    and other_frame_mask
    ora #TILE_USED_MASK
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

    tile_cache_update_set_pre()

    rts
}

// cmd_byte[X&7 to X&7 + cmd_lines] = bits to clear
// Y:X = first line address
function noreturn clr_block()
{
    forever {}
}

// Y: cache line
function tile_cache_update_set_pre()
{
    tya
    asl A
    asl A
    asl A
    tax

    lda #0

    bcs tile_cache_update_set_clear1

    sta tile_cache+7, X
    sta tile_cache+6, X
    sta tile_cache+5, X
    sta tile_cache+4, X
    sta tile_cache+3, X
    sta tile_cache+2, X
    sta tile_cache+1, X
    sta tile_cache+0, X

    jmp tile_cache_update_set

tile_cache_update_set_clear1:
    sta tile_cache+0x107, X
    sta tile_cache+0x106, X
    sta tile_cache+0x105, X
    sta tile_cache+0x104, X
    sta tile_cache+0x103, X
    sta tile_cache+0x102, X
    sta tile_cache+0x101, X
    sta tile_cache+0x100, X


tile_cache_update_set:
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

