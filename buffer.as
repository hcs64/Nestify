// mechanism for keeping track of double buffered tiles

#align 256
 cache_map:
#incbin "cachemap.bin"

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

    ldx #TILE_CACHE_USED_SIZE
    do {
        dex
        sta tile_cache_used, X
    } while (not zero)

    ldx #TILE_CACHE_SIZE
    do {
        dex
        sta tile_cache, X
    } while (not zero)

    lda #DIRTY_FRAME_0
    sta this_frame_mask
    lda #DIRTY_FRAME_1
    sta other_frame_mask
    lda #COUNT_MASK
    sta count_mask_zp
    lda #CACHED_MASK
    sta cached_mask_zp
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
        bit count_mask_zp
        if (zero)
        {
            cmd_tile_clear()
            jmp finish_finished
        }
        
        and #CACHED_MASK
        if (zero)
        {
            cmd_tile_copy()
            jmp finish_finished
        }

        // write from cache
        lda cache_map+page, X
        asl A
        asl A
        asl A
        sta cmd_start
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


// Y:X have block #
inline add_prim()
{
    cpy #0  // last use of Y
    if (equal)
    {
        add_prim_0(0)
    }

    add_prim_0(0x100)
}

inline add_prim_0(page)
{
    lda tile_status+page, X

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
    bit cached_mask_zp
    if (not zero)
    {
        // cached
        ldy cache_map+page, X
        tile_cache_update_set()

        // write back only the changed lines
        cmd_tile_cache_write_lines()
        rts
    }

    // not cached
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
        ldy cache_map+page, X
        lda cache_used_idx, Y
        tay
        lda tile_cache_used, Y

        ldy cache_map+page, X
        and cache_used_mask, Y

        if (zero)
        {
            lda #CACHED_MASK
            ora tile_status+page, X
            sta tile_status+page, X

            ldy cache_map+page, X
            tile_cache_add_lines()
        }
        rts
    }

    // not zero prims
    bit cached_mask_zp
    if (not zero)
    {
        ldy cache_map+page, X
        tile_cache_update_set()

        // write the whole block
        cmd_tile_cache_write()
        rts
    }

    // not cached
    cmd_copy_ora_all_lines()
    rts
}

// Y:X have block #
inline remove_prim()
{
    cpy #0  // last use of Y
    if (equal)
    {
        remove_prim_0(0)
    }
    remove_prim_0(0x100)
}

inline remove_prim_0(page)
{
    lda tile_status+page, X

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
        stx tmp_byte

        cmd_clr_lines()

        ldx tmp_byte
        lda tile_status+page, X

        bit cached_mask_zp
        if (not zero)
        {
            eor #CACHED_MASK
            sta tile_status+page, X

            ldy cache_map+page, X
            tile_cache_remove_lines()
        }

        rts
    }

    // not zero prims

    bit cached_mask_zp
    if (not zero)
    {
        ldy cache_map+page, X
        tile_cache_update_clr()

        cmd_tile_cache_write_lines()
        rts
    }

    // not cached
    cmd_and_lines()
    rts

remove_copy:
    // !TF && OF
    sta tile_status+page, X

    bit count_mask_zp
    if (zero)
    {
        stx tmp_byte

        cmd_tile_clear()

        ldx tmp_byte
        lda tile_status+page, X

        bit cached_mask_zp
        if (not zero)
        {
            eor #CACHED_MASK
            sta tile_status+page, X

            ldy cache_map+page, X
            tile_cache_remove_lines()
        }

        rts
    }

    // not zero prims

    bit cached_mask_zp
    if (not zero)
    {
        ldy cache_map+page, X
        tile_cache_update_clr()

        // write the whole block
        cmd_tile_cache_write()
        rts
    }

    // not cached

    cmd_copy_and_all_lines()
    rts
}

// update cmd_start to with offset into tile_cache
function tile_cache_update_set()
{
    ldx cmd_start

    tya
    asl A
    asl A
    asl A
    ora cmd_start
    sta cmd_start
    tay

    lda cmd_lines
    sta tmp_byte

    do {
        lda cmd_byte, X
        ora tile_cache, Y
        sta tile_cache, Y
        inx
        iny

        dec tmp_byte
    } while (not equal)
}

// update cmd_start to with offset into tile_cache
function tile_cache_update_clr()
{
    ldx cmd_start

    tya
    asl A
    asl A
    asl A
    ora cmd_start
    sta cmd_start
    tay

    lda cmd_lines
    sta tmp_byte

    do {
        lda cmd_byte, X
        and tile_cache, Y
        sta tile_cache, Y
        inx
        iny

        dec tmp_byte
    } while (not equal)
}

// Y: cache line
function tile_cache_add_lines()
{
    lda cache_used_idx, Y
    tax
    lda tile_cache_used, X

    ora cache_used_mask, Y
    sta tile_cache_used, X

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
    lda cache_used_idx, Y
    tax
    lda tile_cache_used, X

    and cache_used_clr_mask, Y
    sta tile_cache_used, X

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
    lda cache_used_idx, Y
    tax
    lda tile_cache_used, X

    and cache_used_clr_mask, Y
    sta tile_cache_used, X

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

byte cache_used_idx[31] = {
    0,0,0,0,0,0,0,0,
    1,1,1,1,1,1,1,1,
    2,2,2,2,2,2,2,2,
    3,3,3,3,3,3,3
}
byte cache_used_mask[31] = {
    $80,$40,$20,$10,$08,$04,$02,$01,
    $80,$40,$20,$10,$08,$04,$02,$01,
    $80,$40,$20,$10,$08,$04,$02,$01,
    $80,$40,$20,$10,$08,$04,$02
}
byte cache_used_clr_mask[31] = {
    $7f,$bf,$df,$ef,$f7,$fb,$fd,$fe,
    $7f,$bf,$df,$ef,$f7,$fb,$fd,$fe,
    $7f,$bf,$df,$ef,$f7,$fb,$fd,$fe,
    $7f,$bf,$df,$ef,$f7,$fb,$fd
}
