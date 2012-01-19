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

    ldx #4
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
}

function clear_screen()
{
    // TODO: this needs to be able to flush the cache as well
    ldx #0
    do {
        lda tile_status, X
        bit count_mask_rom
        if (not zero)
        {
            lda #DIRTY_FRAME_0|DIRTY_FRAME_1
            sta tile_status, X
        }

        dex
    } while (not zero)

    ldx #(TILES_WIDE*TILES_HIGH)-0x100
    do {
        lda tile_status+0x100-1, X
        bit count_mask_rom
        if (not zero) {
            lda #DIRTY_FRAME_0|DIRTY_FRAME_1
            sta tile_status+0x100-1, X
        }
        dex
    } while (not zero)
}

inline tracktiles_finish_frame0(count, countdirop, page)
{
    ldx #count
    do {
        countdirop
        stx tmp_byte2

        lda tile_status+(page*0x100), X

        bit cached_mask_rom
        beq check_other_frame
        bit other_frame_mask
        bne writeback_tile_other_frame
        bit this_frame_mask
        beq done_flush_tile
        bne writeback_tile_this_frame

writeback_tile_other_frame:
        eor other_frame_mask
        sta tile_status+(page*0x100), X

writeback_tile_this_frame:

            stx cmd_addr+0
            lda #page
            asl cmd_addr+0
            rol A
            asl cmd_addr+0
            rol A
            asl cmd_addr+0
            rol A
            ora cur_nametable_page
            sta cmd_addr+1

            lda cache_map+(page*0x100), X
            asl A
            asl A
            asl A
            sta cmd_start

            cmd_tile_cache_writeback()

            jmp done_flush_tile

 check_other_frame:
        bit other_frame_mask
        beq done_flush_tile

flush_tile_other_frame:
            eor other_frame_mask
            sta tile_status+(page*0x100), X
            and #COUNT_MASK
            tay

            stx cmd_addr+0
            lda #page
            asl cmd_addr+0
            rol A
            asl cmd_addr+0
            rol A
            asl cmd_addr+0
            rol A
            ora cur_nametable_page
            sta cmd_addr+1

            cpy #0
            if (zero)
            {
                cmd_tile_clear()
            }
            else
            {
                cmd_tile_copy()
            }
done_flush_tile:

        ldx tmp_byte2
    } while (not zero)
}

function tracktiles_finish_frame()
{
    // update any stragglers from last frame, or cached dirties from this
    tracktiles_finish_frame0(0,inx,0)
    tracktiles_finish_frame0( (TILES_WIDE*TILES_HIGH)-0x100, dex, 1)

    // swap masks
    lda this_frame_mask
    ldx other_frame_mask
    sta other_frame_mask
    stx this_frame_mask
}


// Y:X have block #
inline add_prim(clean_noprev, clean_prev, dirty_noprev, dirty_prev, update_cache, add_cache)
{
    cpy #0
    if (equal) {
        add_prim_0(0, clean_noprev, clean_prev, dirty_noprev, dirty_prev, update_cache, add_cache)
        rts
    } else {
        add_prim_0(0x100, clean_noprev, clean_prev, dirty_noprev, dirty_prev, update_cache, add_cache)
    }
}

inline add_prim_0(page, clean_noprev, clean_prev, dirty_noprev, dirty_prev, update_cache, add_cache)
{
    lda tile_status+page, X

    bit count_mask_rom
    if (zero) {

        ldy cache_map+page, X
        lda cache_used_idx, Y
        tay
        lda tile_cache_used, Y

        ldy cache_map+page, X
        and cache_used_mask, Y

        if (zero) {
            // set cached now, first prim, ignore dirty prev frame (blank)
            lda #CACHED_MASK|1
            ora this_frame_mask
            sta tile_status+page, X

            //
            ldy cache_map+page, X
            add_cache()
            rts
        }

        lda tile_status+page, X
        ora this_frame_mask
        ora #1

        bit other_frame_mask
        if (not zero) {
            eor other_frame_mask
            sta tile_status+page, X

            // set ok, tile is dirty
            dirty_noprev()
            rts
        }

        sta tile_status+page, X

        // set ok, tile is clean
        clean_noprev()
        rts
    }

    // at least one prim already
    ora this_frame_mask
    clc
    adc #1

    bit cached_mask_rom
    if (not zero) {
        bit other_frame_mask
        if (not zero)
        {
            // never mind other frame, cache is up to date
            eor other_frame_mask    
        }
        sta tile_status+page, X

        //
        ldy cache_map+page, X
        update_cache()
        rts
    }

    bit other_frame_mask
    if (not zero) {
        eor other_frame_mask
        sta tile_status+page, X

        // copy needed, tile is dirty
        dirty_prev()
        rts
    }

    sta tile_status+page, X

    // update needed, tile is clean
    clean_prev()
    rts
}

// Y:X have block #
inline remove_prim(clean_last, clean_notlast, dirty_last, dirty_notlast, update_cache, remove_cache)
{
    cpy #0
    if (equal) {
        remove_prim_0(0, clean_last, clean_notlast, dirty_last, dirty_notlast, update_cache, remove_cache)
        rts
    } else {
        remove_prim_0(0x100, clean_last, clean_notlast, dirty_last, dirty_notlast, update_cache, remove_cache)
    }
}

inline remove_prim_0(page, clean_last, clean_notlast, dirty_last, dirty_notlast, update_cache, remove_cache)
{
    lda tile_status+page, X
    ora this_frame_mask

    sec
    sbc #1

    bit count_mask_rom
    if (zero) {
        bit cached_mask_rom
        if (not zero) {
            // ensure 'twill be cleared at end of frame
            ora other_frame_mask

            eor #CACHED_MASK    // clear the cache flag now
            sta tile_status+page, X

            //
            ldy cache_map+page, X
            remove_cache()
            rts
        }

        bit other_frame_mask
        if (not zero) {

            eor other_frame_mask
            sta tile_status+page, X

            // clear ok, tile is dirty
            dirty_last()
            rts
        }

        sta tile_status+page, X

        // clear ok, tile is clean
        clean_last()
        rts
    }

    // not down to zero prims

    bit cached_mask_rom
    if (not zero) {
        bit other_frame_mask
        if (not zero) {
            // never mind other frame, cache is up to date
            eor other_frame_mask    
        }
        sta tile_status+page,X

        //
        ldy cache_map+page, X
        update_cache()
        rts
    }

    bit other_frame_mask
    if (not zero) {
        eor other_frame_mask
        sta tile_status+page, X

        // copy needed, tile is dirty
        dirty_notlast()
        rts
    }

    sta tile_status+page, X

    // update needed, tile is clean
    clean_notlast()
    rts
}


function tile_cache_update_set()
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
        ora tile_cache, Y
        sta tile_cache, Y
        inx
        iny

        dec cmd_lines
    } while (not equal)
}

function tile_cache_update_clr()
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
        and tile_cache, Y
        sta tile_cache, Y
        inx
        iny

        dec cmd_lines
    } while (not equal)
}

// Y: cache line
function tile_cache_add()
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

// a few handy values for BITs
byte count_mask_rom[1] = {COUNT_MASK}
byte cached_mask_rom[1] = {CACHED_MASK}
byte set_v_rom[1] = {0x40|COUNT_MASK}

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
