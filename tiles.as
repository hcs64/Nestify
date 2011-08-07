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

    lda #DIRTY_FRAME_1+2
    sta tile_status+0

    lda #DIRTY_FRAME_0
    sta this_frame_mask
    lda #DIRTY_FRAME_1
    sta other_frame_mask
}

function tracktiles_finish_frame()
{
    // update any stragglers from last frame
    ldx #0
    do {
        inx
        stx tmp_byte2

        lda tile_status, X
        bit other_frame_mask
        if (not zero) {
            eor other_frame_mask
            sta tile_status, X

            ldy #0
            sty cmd_addr+1
            txa
            asl A
            rol cmd_addr+1
            asl A
            rol cmd_addr+1
            asl A
            rol cmd_addr+1
            sta cmd_addr+0

            cmd_tile_copy()
        }

        ldx tmp_byte2
    } while (not zero)

    ldx #(TILES_WIDE*TILES_HIGH)-0x100
    do {
        dex
        stx tmp_byte2

        lda tile_status+0x100, X
        bit other_frame_mask
        if (not zero) {
            eor other_frame_mask
            sta tile_status+0x100, X

            ldy #1
            sty cmd_addr+1
            txa
            asl A
            rol cmd_addr+1
            asl A
            rol cmd_addr+1
            asl A
            rol cmd_addr+1
            sta cmd_addr+0

            cmd_tile_copy()
        }

        ldx tmp_byte2
    } while (not zero)

    lda this_frame_mask
    ldx other_frame_mask
    sta other_frame_mask
    stx this_frame_mask
}

// Y:X have block #
// preserves X and Y
// return Z clear if whole tile must be updated
// return C set if set is ok
function add_prim()
{
    cpy #0
    if (equal) {
        add_prim_0(0)
        rts
    } else {
        add_prim_0(0x100)
    }
}

inline add_prim_0(page)
{
    lda tile_status+page, X
    ora this_frame_mask

    bit count_mask_rom
    if (zero) {
        ora #1  // first count
        bit other_frame_mask
        sec
        if (not equal) {
            eor other_frame_mask
            sta tile_status+page, X
            // set ok, tile is dirty
            rts
        }

        sta tile_status+page, X
        lda #0  // set Z
        // set ok, tile is clean
        rts
    }

    // at least one prim already
    clc
    adc #1
    bit other_frame_mask
    if (not equal) {
        eor other_frame_mask
        sta tile_status+page, X
        // copy needed, tile is dirty
        rts
    }
    sta tile_status+page, X
    lda #0  // set Z
    // update needed, tile is clean
}

// Y:X have block #
// preserves X and Y
// return Z clear if whole tile must be updated
// return C set if bulk clear is ok
function remove_prim()
{
    cpy #0
    if (equal) {
        remove_prim_0(0)
        rts
    } else {
        remove_prim_0(0x100)
    }
}

inline remove_prim_0(page)
{
    lda tile_status+page, X
    ora this_frame_mask

    sec
    sbc #1

    bit count_mask_rom
    if (zero) {
        bit other_frame_mask
        sec
        if (not equal) {
            eor other_frame_mask
            sta tile_status+page, X
            // clear ok, tile is dirty
            rts
        }

        sta tile_status+page, X
        lda #0  // set Z
        // clear ok, tile is clean
        rts
    }

    // not down to zero prims
    clc
    bit other_frame_mask
    if (not equal) {
        eor other_frame_mask
        sta tile_status+page, X
        // copy needed, tile is dirty
        rts
    }
    sta tile_status+page, X
    lda #0  // set Z
    // update needed, tile is clean
}

byte count_mask_rom[1] = {0x1f}
