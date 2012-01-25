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

    ldx #TILE_CACHE_SIZE
    do {
        dex
        sta tile_cache, X
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
        if (minus)
        {
            // write from cache
            and #CACHE_LINE_MASK
            asl A
            asl A
            asl A
            sta cmd_start

            cmd_tile_cache_write()

            jmp finish_finished
        }

        bit count_mask_zp
        if (zero)
        {
            cmd_tile_clear()
            jmp finish_finished
        }
        
        cmd_tile_copy()

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


// Y:X have block #
inline add_prim()
{
    cpy #0  // last use of Y
    bne add_prim_100
    lda tile_status, X
    bmi add_cached_0
    add_prim_0(0)

add_cached_0:
    add_prim_cached_0(0)

add_prim_100:
    lda tile_status+0x100, X
    bmi add_cached_100
    add_prim_0(0x100)

add_cached_100:
    add_prim_cached_0(0x100)
}

inline add_prim_cached_0(page)
{
    // cached

    // not zero prims (implicitly)

    bit this_frame_mask
    bne add_cached_update
    ora this_frame_mask
    sta tile_status+page, X

    bit other_frame_mask
    bne add_cached_copy

add_cached_update:
    and #CACHE_LINE_MASK
    tax
    inc tile_cache_list, X
    tile_cache_update_set()

    // write back only the changed lines
    cmd_tile_cache_write_lines()
    rts

add_cached_copy:
    and #CACHE_LINE_MASK
    tax
    inc tile_cache_list, X
    
    tile_cache_update_set()

    // write the whole block
    cmd_tile_cache_write()
    rts
}

inline add_prim_0(page)
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
            and #~CACHE_LINE_MASK
            ora #CACHED_MASK
            ora tile_cache_free_ptr
            sta tile_status+page, X

            // point free list head at next
            lda tile_cache_list, Y
            sta tile_cache_free_ptr

            // now use free list entry for prim count
            lda #1
            sta tile_cache_list, Y

            tile_cache_add_lines()
        }
        rts
    }

    // not zero prims
    cmd_copy_ora_all_lines()
    rts
}

// Y:X have block #
inline remove_prim()
{
    cpy #0  // last use of Y
    bne remove_prim_100

    lda tile_status, X
    bmi remove_cached_0
    remove_prim_0(0)

remove_prim_100:
    lda tile_status+0x100, X
    bmi remove_cached_100
    remove_prim_0(0x100)

remove_cached_0:
    remove_prim_cached_0(0)

remove_cached_100:
    remove_prim_cached_0(0x100)
}

inline remove_prim_cached_0(page)
{
    stx tmp_byte

    bit this_frame_mask
    bne remove_cached_update
    ora this_frame_mask
    sta tile_status+page, X

    bit other_frame_mask
    bne remove_cached_copy

remove_cached_update:

    and #CACHE_LINE_MASK
    tax

    dec tile_cache_list, X

    if (zero)
    {
        cmd_clr_lines()

evict_from_cache:
        ldx tmp_byte
        lda tile_status+page, X
        tay
        and #CACHE_LINE_MASK
        tax

        // take it off the free list
        lda tile_cache_free_ptr
        sta tile_cache_list, X
        stx tile_cache_free_ptr

        tya
        and #~(CACHED_MASK|CACHE_LINE_MASK)
        ldx tmp_byte
        sta tile_status+page, X

        ldy tile_cache_free_ptr

        tile_cache_remove_lines()

        rts
    }
    
    tile_cache_update_clr()

    cmd_tile_cache_write_lines()

    rts

remove_cached_copy:

    and #CACHE_LINE_MASK
    tax

    dec tile_cache_list, X

    if (zero)
    {
        cmd_tile_clear()

        jmp evict_from_cache
    }

    tile_cache_update_clr()

    cmd_tile_cache_write()

    rts

}

inline remove_prim_0(page)
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

// X: cache line
// update cmd_start to offset into tile_cache
function tile_cache_update_set()
{
    ldy cmd_start

    txa
    asl A
    asl A
    asl A
    ora cmd_start
    sta cmd_start
    tax

    lda cmd_lines
    sta tmp_byte

    do {
        lda cmd_byte, Y
        ora tile_cache, X
        sta tile_cache, X
        inx
        iny

        dec tmp_byte
    } while (not equal)
}

// X: cache page
// update cmd_start to offset into tile_cache
function tile_cache_update_clr()
{
#tell.bankoffset
    ldy cmd_start

    txa
    asl A
    asl A
    asl A
    ora cmd_start
    sta cmd_start
    tax

    lda cmd_lines
    sta tmp_byte

    do {
        lda cmd_byte, Y
        and tile_cache, X
        sta tile_cache, X
        inx
        iny

        dec tmp_byte
    } while (not equal)
}

// Y: cache line
function tile_cache_add_lines()
{
    //
    tya
    asl A
    asl A
    asl A
    ora cmd_start
    tay

    ldx cmd_start
    do {
        lda cmd_byte, X
        sta tile_cache, Y
        inx
        iny

        dec cmd_lines
    } while (not equal)
}

// Y: cache line
function tile_cache_remove()
{
    //
    tya
    asl A
    asl A
    asl A
    tay

    lda #0
    ldx #8
    do {
        sta tile_cache, Y
        iny
        dex
    } while (not zero)
}

// Y: cache line
function tile_cache_remove_lines()
{
    //
    tya
    asl A
    asl A
    asl A
    ora cmd_start
    tay

    lda #0
    ldx cmd_lines
    while (not zero) {
        sta tile_cache, Y
        iny
        dex
    }
}
