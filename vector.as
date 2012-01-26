/******************************************************************************/

word right_adjust_rom[2] = {-( (8*2*11) - 8), (8*2)}
byte pixel_pos_set_rom[8] = {$80,$40,$20,$10,$08,$04,$02,$01}
byte pixel_pos_clr_rom[8] = {$7F,$BF,$DF,$EF,$F7,$FB,$FD,$FE}

function bresenham_set()
{
    bresenham_setup()

    txa
    if (minus)
    {
        tya
        if (zero)
        {
            bresenham_HPY_set()
        }
        else
        {
            bresenham_HNY_set()
        }
        rts
    }
    else
    {
        txa
        if (zero)
        {
            bresenham_VPX_set()
        }
        else
        {
            bresenham_VNX_set()
        }
    }
}

function bresenham_clr()
{
    bresenham_setup()

    txa
    if (minus)
    {
        tya
        if (zero)
        {
            bresenham_HPY_clr()
        }
        else
        {
            bresenham_HNY_clr()
        }
        rts
    }
    else
    {
        txa
        if (zero)
        {
            bresenham_VPX_clr()
        }
        else
        {
            bresenham_VNX_clr()
        }
    }
}

function bresenham_VPX_set()
{
    bresenham_VPX(or_block, bcc, pixel_pos_set_rom, set_shift_right)
}
function bresenham_VPX_clr()
{
    bresenham_VPX(clr_block, bcs, pixel_pos_clr_rom, clr_shift_right)
}
function bresenham_VNX_set()
{
    bresenham_VNX(or_block, bcc, pixel_pos_set_rom, set_shift_left)
}
function bresenham_VNX_clr()
{
    bresenham_VNX(clr_block, bcs, pixel_pos_clr_rom, clr_shift_left)
}
function bresenham_HPY_set()
{
    bresenham_HPY(or_block, 0)
}
function bresenham_HPY_clr()
{
    bresenham_HPY(clr_block, 0xFF)
}
function bresenham_HNY_set()
{
    bresenham_HNY(or_block, 0)
}
function bresenham_HNY_clr()
{
    bresenham_HNY(clr_block, 0xFF)
}

function bresenham_setup()
{
    ldy #0
    ldx #0

    stx line_err_strt+1

    sec
    lda line_x1
    sbc line_x0
    if (not carry) {
        eor #$ff
        clc
        adc #1
        inx
    }
    sta tmp_byte

    sec
    lda line_y1
    sbc line_y0
    if (not carry) {
        eor #$ff
        clc
        adc #1
        iny
    }

    cmp tmp_byte
    if (not carry)
    {
        // Y minor
        // compute 2*DMin (error adjustment when going straight)
        asl A
        sta line_err_strt+0
        rol line_err_strt+1

        // X major
        // compute DMaj (number of iterations)
        lda tmp_byte
        sta line_iters

        // always inc along the major axis
        txa
        if (not zero)
        {
            ldx line_x0
            lda line_x1
            sta line_x0
            stx line_x1

            ldx line_y0
            lda line_y1
            sta line_y0
            stx line_y1

            tya
            eor #1
            tay
        }

        ldx #$80
    }
    else
    {
        // Y major
        // compute DMaj (number of iterations)
        sta line_iters

        // X minor
        // compute 2*DMin (error adjustment when going straight)
        lda tmp_byte
        asl A
        sta line_err_strt+0
        rol line_err_strt+1

        // always inc along the major axis
        tya
        if (not zero)
        {
            ldy line_x0
            lda line_x1
            sta line_x0
            sty line_x1

            ldy line_y0
            lda line_y1
            sta line_y0
            sty line_y1

            txa
            eor #1
            tax
        }

        ldy #$80
    }

    // compute 2*DMin-DMaj (initial error)
    sec
    lda line_err_strt+0
    sbc line_iters
    sta line_err0
    lda line_err_strt+1
    sbc #0
    sta line_err1

    // compute 2*DMin-2*DMaj (error adjustment when going diagonally)
    sec
    lda line_err0
    sbc line_iters
    sta line_err_diag+0
    lda line_err1
    sbc #0
    sta line_err_diag+1

    // always cover the last pixel
    inc line_iters
}

function bresenham_common_setup()
{
    lda #0
    sta tmp_byte
    sta line_block1

    // x coordinate in blocks
    lda line_x0
    lsr A
    lsr A
    lsr A
    sta line_x_block

    // calculate first block index
    lda line_x0
    and #~7
    cmp #(12*8)
    if (not minus)
    {
        sec
        sbc #( (12*8) - (8/2) )
    }
    asl A
    sta line_block0
    rol line_block1

    // y/8*8*2*12
    lda line_y0
    tay
    and #~7

    // +8y
    asl A
    rol tmp_byte
    asl A
    rol tmp_byte
    asl A
    rol tmp_byte
    tax
    clc
    adc line_block0
    sta line_block0
    lda tmp_byte
    adc line_block1
    sta line_block1

    // +16y
    txa
    asl A
    rol tmp_byte
    clc
    adc line_block0
    sta line_block0
    lda tmp_byte
    adc line_block1
    sta line_block1

    // only interested in the sub-block offset
    tya
    and #7
    sta line_y0
}

inline bresenham_HNY(cmd_fcn, empty_row) {
    bresenham_H_common(cmd_fcn, empty_row, bresenham_up_fcn)
}

inline bresenham_HPY(cmd_fcn, empty_row) {
    bresenham_H_common(cmd_fcn, empty_row, bresenham_down_fcn)
}

inline clr_shift_right() {
    sec
    ror line_row
}

inline set_shift_right() {
    lsr line_row
}

inline clr_shift_left() {
    sec
    rol line_row
}

inline set_shift_left() {
    asl line_row
}

inline bresenham_down_fcn(cmd_fcn, empty_row) {
    // move down a line
    ldx line_y0
    inx

    // check if we're done with this block vertically
    cpx #8
    if (equal)
    {
        // is this block new already?
        lda cmd_byte+7
        cmp #empty_row
        if (not equal)
        {
            // send this block
            ldx line_block0
            ldy line_block1

            cmd_fcn()
        }

        // begin a new block
        ldx #0
        stx cmd_start
        stx line_y0
        lda #1
        sta cmd_lines

        // move to next block down
        clc
        lda line_block0
        adc #(12*8*2)
        sta line_block0
        lda line_block1
        adc #0
        sta line_block1

    }
    else
    {
        stx line_y0
        inc cmd_lines
    }

    // start with an empty line
    lda #empty_row
    sta cmd_byte, X
}

inline bresenham_up_fcn(cmd_fcn, empty_row) {
    // move up a line
    ldx line_y0
    dex

    // check if we're done with this block vertically
    if (minus)
    {
        // is this block new already?
        lda cmd_byte
        cmp #empty_row
        if (not equal)
        {
            // send this block
            ldx line_block0
            ldy line_block1

            cmd_fcn()
        }

        // begin a new block
        ldx #7
        stx cmd_start
        stx line_y0
        lda #1
        sta cmd_lines

        // move to next block up
        sec
        lda line_block0
        sbc #(12*8*2)
        sta line_block0
        lda line_block1
        sbc #0
        sta line_block1
    }
    else
    {
        inc cmd_lines
        dec cmd_start
        stx line_y0
    }

    // start with an empty line
    lda #empty_row
    sta cmd_byte, X
}

inline bresenham_H_common(cmd_fcn, empty_row, updown_fcn) {
    bresenham_common_setup()

    // pixel position
    lda line_x0
    and #7
    tax
    lda pixel_pos_set_rom, X
    sta line_row

    // begin a new block
    ldx line_y0
    stx cmd_start
    lda #1
    sta cmd_lines

    // start with an empty line
    lda #empty_row
    sta cmd_byte, X

    // do them columns
    forever {
        // plot!
        ldx line_y0
        lda line_row
        eor cmd_byte, X
        sta cmd_byte, X

        lsr line_row

        // check if we're done with this block horizontally
        if (carry)
        {
            // wrap pixel around
            ror line_row

            // send it
            ldx line_block0
            ldy line_block1

            cmd_fcn()

            // maybe that's all
            dec line_iters
            if (equal) {
                rts
            }

            // move to next block right
            inc line_x_block
            lda line_x_block
            sec
            sbc #12
            tax

            if (not equal)
            {
                // straightforward adjust (8*2)
                ldx #2
            }

            clc
            lda line_block0
            adc right_adjust_rom+0, X
            sta line_block0
            lda line_block1
            adc right_adjust_rom+1, X
            sta line_block1

            // begin a new block
            ldx line_y0
            stx cmd_start
            lda #1
            sta cmd_lines

            // start with an empty line
            lda #empty_row
            sta cmd_byte, X
        }
        else
        {
            dec line_iters
            if (equal) {
                // send whatever we did so far

                ldx line_block0
                ldy line_block1

                cmd_fcn()

                rts
            }
        }

        // go up/down as well?
        ldx #0
        bit line_err1
        if (not minus)
        {
            updown_fcn(cmd_fcn, empty_row)

            ldx #2
        }

        // adjust error
        clc
        lda line_err0
        adc line_err_strt+0, X
        sta line_err0
        lda line_err1
        adc line_err_strt+1, X
        sta line_err1
    }
}

inline bresenham_VNX(cmd_fcn, wrap_check, pixel_pos_rom, shift_cmd) {
    bresenham_V_common(cmd_fcn, wrap_check, pixel_pos_rom, bresenham_left_fcn, shift_cmd, rol)
}

inline bresenham_VPX(cmd_fcn, wrap_check, pixel_pos_rom, shift_cmd) {
    bresenham_V_common(cmd_fcn, wrap_check, pixel_pos_rom, bresenham_right_fcn, shift_cmd, ror)
}

inline bresenham_right_fcn() {
    // move to next block right
    inc line_x_block
    lda line_x_block
    sec
    sbc #12
    tax

    if (not equal)
    {
        // straightforward adjust (8*2)
        ldx #2
    }
    
    clc
    lda line_block0
    adc right_adjust_rom+0, X
    sta line_block0
    lda line_block1
    adc right_adjust_rom+1, X
    sta line_block1
}

inline bresenham_left_fcn() {
    // move to next block left
    dec line_x_block
    lda line_x_block
    sec
    sbc #11
    tax

    if (not equal)
    {
        // straightforward adjust (8*2)
        ldx #2
    }
    
    sec
    lda line_block0
    sbc right_adjust_rom+0, X
    sta line_block0
    lda line_block1
    sbc right_adjust_rom+1, X
    sta line_block1
}

inline bresenham_V_common(cmd_fcn, wrap_check, pixel_pos_rom, rightleft_fcn, shift_cmd, rot_op) {
    bresenham_common_setup()

    // pixel position
    lda line_x0
    and #7
    tax
    lda pixel_pos_rom, X
    sta line_row

    // begin a new block
    lda #0
    sta cmd_lines
    lda line_y0
    sta cmd_start

    // do them rows
    forever {
        ldy line_y0
        iny
        sty line_y0

        // plot!
        lda line_row
        sta cmd_byte-1, Y

        inc cmd_lines

        // check if we're done with this block vertically
        cpy #8
        if (equal)
        {
            // yes, send it
            ldx line_block0
            ldy line_block1

            cmd_fcn()

            // maybe that's all
            dec line_iters
            if (equal) {
                rts
            }

            // begin a new block
            lda #0
            sta cmd_lines
            sta line_y0
            sta cmd_start

            // move to next block down
            clc
            lda line_block0
            and #~7
            adc #(12*8*2)
            sta line_block0
            lda line_block1
            adc #0
            sta line_block1
        }
        else
        {
            dec line_iters
            if (equal) {
                // send the last block

                ldx line_block0
                ldy line_block1

                cmd_fcn()

                rts
            }
        }

        // go left/right as well?
        ldx #0
        bit line_err1
        if (not minus)
        {
            shift_cmd
            wrap_check no_wrap
                // wrap pixel around
                rot_op line_row

                // check if this isn't a new block
                lda cmd_lines
                if (not zero)
                {
                    // we had previously written to the current block

                    // send it
                    ldx line_block0
                    ldy line_block1

                    cmd_fcn()

                    // begin a new block
                    lda #0
                    sta cmd_lines
                    lda line_y0
                    sta cmd_start
                }

                rightleft_fcn()
no_wrap:

            ldx #2
        }

        // adjust error
        clc
        lda line_err0
        adc line_err_strt+0, X
        sta line_err0
        lda line_err1
        adc line_err_strt+1, X
        sta line_err1
    }
}
function finish_frame()
{
    tracktiles_finish_frame()
    dlist_finish_frame()

    /*
    lda frame_counter
    sta last_frame_time
    ldx #0
    stx frame_counter

    cmp highest_frame_time
    if (carry) {
        sta highest_frame_time
    }
    */

    lda cur_nametable_page
    eor #0x10
    sta cur_nametable_page
}
