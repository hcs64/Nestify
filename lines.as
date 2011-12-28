// top level update commands

// cmd_byte[X&7 to X&7 + cmd_lines] = bits to OR with
// Y:X = first line address
function or_block()
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
    ldy tmp_byte

    add_prim()

    lda #$09 // ora imm
    sta cmd_op

    lda #8
    sta cmd_lines

    lda cmd_addr+0
    and #7
    sta cmd_start

    if (zero) {
        // tile is clean

        if (carry) {
            // no previous prim, set is ok
            cmd_set_lines()
        } else {
            // lay on top of existing prims
            cmd_X_update_lines()
        }
    }
    else
    {
        // tile is dirty

        if (carry) {
            // no previous prim, set entire block
            cmd_set_all_lines()
        } else {
            // copy previous frame + set
            cmd_X_copy_all_lines()
        }
    }
}

// cmd_byte[X&7 to X&7 + cmd_lines] = bits to clear
// Y:X = first line address
function clr_block()
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
    ldy tmp_byte

    remove_prim()

    lda #$29 // and imm
    sta cmd_op

    lda #8
    sta cmd_lines

    lda cmd_addr+0
    and #7
    sta cmd_start

    if (zero) {
        // tile is clean

        if (carry) {
            // no remaining prim, clear is ok
            cmd_clr_lines()
        } else {
            // clear bits in preexisting prims
            cmd_X_update_lines()
        }
    }
    else
    {
        // tile is dirty

        if (carry) {
            // no previous prim, clear entire block
            cmd_tile_clear()
        } else {
            // copy previous frame + clear
            cmd_X_copy_all_lines()
        }
    }
}

function finish_frame()
{
    tracktiles_finish_frame()
    sendchr_finish_frame()

    lda frame_counter
    sta last_frame_time
    lda #0
    sta frame_counter

    lda cur_nametable_page
    eor #0x10
    sta cur_nametable_page
}
