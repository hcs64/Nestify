// top level update commands

// Y:X = line address (8x block addres + line offset)
function or_line()
{
    sta cmd_byte
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
    ldy tmp_byte

    add_prim()

    if (zero) {
        // tile is clean

        if (carry) {
            // no previous prim, set is ok
            cmd_set_one_byte()
        } else {
            // need to update (just this byte)
            cmd_or_one_byte()
        }
    }
    else
    {
        // tile is dirty

        php

        lda cmd_addr+0
        and #7
        sta tmp_byte

        lda cmd_byte
        ldx #0

        ldy #7
        do {
            cpy tmp_byte
            if (equal)
            {
                sta cmd_byte, Y
            } else {
                stx cmd_byte, Y
            }
            dey
        } while (not minus)

        lda cmd_addr+0
        and #~7
        sta cmd_addr+0

        plp

        if (carry) {
            // no previous prim, set is ok
            cmd_tile_set()
        } else {
            // need to copy
            cmd_or_tile_copy()
        }
    }
}

// Y:X = line address (8x block addres + line offset)
function and_line()
{
    sta cmd_byte
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
    ldy tmp_byte

    remove_prim()

    if (zero) {
        // tile is clean

        if (carry) {
            // no remaining prim, clear is ok
            lda #0
            sta cmd_byte
            cmd_set_one_byte()
        } else {
            // need to update (just this byte)
            cmd_and_one_byte()
        }
    }
    else
    {
        // tile is dirty

        php

        lda cmd_addr+0
        and #7
        sta tmp_byte

        lda cmd_byte
        ldx #0xFF

        ldy #7
        do {
            cpy tmp_byte
            if (equal)
            {
                sta cmd_byte, Y
            } else {
                stx cmd_byte, Y
            }
            dey
        } while (not minus)

        lda cmd_addr+0
        and #~7
        sta cmd_addr+0

        plp

        if (carry) {
            // no remaining prim, clear is ok
            cmd_tile_clear()
        } else {
            // need to copy
            cmd_and_tile_copy()
        }
    }
}

function finish_frame()
{
    tracktiles_finish_frame()
    sendchr_finish_frame()

    lda cur_nametable_page
    eor #0x10
    sta cur_nametable_page
}
