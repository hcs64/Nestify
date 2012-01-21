// top level update commands

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
    ldy tmp_byte

    lda #$09 // ora imm
    sta cmd_op

    add_prim()
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
    ldy tmp_byte

    lda #$29 // and imm
    sta cmd_op

    remove_prim()
}
