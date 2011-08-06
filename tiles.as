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

    lda #DIRTY_FRAME_0
    sta this_frame_mask
    lda #DIRTY_FRAME_1
    sta other_frame_mask
}

function tracktiles_finish_frame()
{
    lda this_frame_mask
    ldx other_frame_mask
    sta other_frame_mask
    stx this_frame_mask
}

// Y:X have block #
function add_prim()
{
    cpy #0
    if (equal) {
        ldy tile_status, X
        iny
        tya
        ora this_frame_mask
        sta tile_status, X
        rts
    } else {
        ldy tile_status+0x100, X
        iny
        tya
        ora this_frame_mask
        sta tile_status+0x100, X
    }
}

// Y:X have block #
function remove_prim()
{
    cpy #0
    if (equal) {
        ldy tile_status, X
        dey
        tya
        ora this_frame_mask
        sta tile_status, X
        rts
    } else {
        ldy tile_status+0x100, X
        dey
        tya
        ora this_frame_mask
        sta tile_status+0x100, X
    }
}
