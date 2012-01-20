#define TILES_WIDE 24
#define TILES_HIGH 21

#ram.org 0x0, 0x50

pointer tmp_addr
byte    tmp_byte
byte    tmp_byte2
byte    tmp_byte3

// only used by NMI after init
shared byte _ppu_ctl0, _ppu_ctl1

// only set by NMI after init
shared byte _joypad0

struct hold_count_joypad0
{
    byte RIGHT, LEFT, DOWN, UP, START, SELECT, A, B
}
struct repeat_count_joypad0
{
    byte RIGHT, LEFT, DOWN, UP, START, SELECT, A, B
}

// main thread input tracking
shared byte _joypad0_acc
byte last_joypad0
byte new_joypad0

// tile status bits
byte this_frame_mask
byte other_frame_mask

byte cur_nametable_page

// always set by NMI, use to check if ops could be interrupted
byte nmi_hit
byte irq_temp
byte nmi_temp

// small dlist stuff
word dlist_cycles_left
byte dlist_reset_cycles

byte dlist_start_jmp
word dlist_start

word dlist_write_limit // a copy of dlist_start, possibly old
word dlist_next_byte

word dlist_cmd_first_inst_addr
byte dlist_cmd_first_inst_byte

byte tile_cache_used[2] // 15 bits

word cmd_addr
byte cmd_start
byte cmd_lines
byte cmd_op
byte cmd_byte[8]

// only check_for_space_and_cycles() uses these
byte cmd_size   // reused for operation line range
byte cmd_cycles
#ram.end

#ram.org 0x50, 0x10
// 0x50
shared byte frame_counter
// 0x51
byte last_frame_time
// 0x52
word incomplete_vblanks
// 0x54
word complete_vblanks
// 0x56
word stuck_cnt
// 0x58
byte highest_frame_time

byte test_angle
byte test_speed
byte test_count

byte head_poly, tail_poly

#ram.end

#ram.org 0x60, 0x20
// if we need space this can be put out of zero page with no extra cycle cost as
// long as it doesn't cross a page boundary
byte flip_nametable[0x20]
#ram.end

#ram.org 0x80, 0x11
byte line_x0
byte line_y0
byte line_x1
byte line_y1

byte line_row
byte line_iters
byte line_x_block
word line_block
word line_err
word line_err_strt
word line_err_diag
#ram.end

#ram.org 0xD1, 0x2f
byte zp_writer[7]   //      stx $2006 ; sty $2006 ; lda #
byte zp_immed_0[5]  // NN ; sta $2007 ; lda #
byte zp_immed_1[5]  // NN ; sta $2007 ; lda #
byte zp_immed_2[5]  // NN ; sta $2007 ; lda #
byte zp_immed_3[5]  // NN ; sta $2007 ; lda #
byte zp_immed_4[5]  // NN ; sta $2007 ; lda #
byte zp_immed_5[5]  // NN ; sta $2007 ; lda #
byte zp_immed_6[5]  // NN ; sta $2007 ; lda #
byte zp_immed_7[5]  // NN ; sta $2007 ; rts

#ram.end

#ram.org 0x100, 0x20
// stack
byte stack[0x20]
stack_end:
#ram.end


#ram.org 0x120, 0x420

#define DLIST_SIZE 0x420
#define DLIST_WORST_CASE_SIZE (DLIST_SIZE-4)

byte dlist_0[DLIST_SIZE]
#define DLIST_LAST_CMD_START (dlist_0+DLIST_WORST_CASE_SIZE)

#ram.end

#ram.org 0x540, 0x50

#define NUM_POLYS 4
#define POLY_WRAP_MASK %110000
typedef struct point_s {
    byte x, y, vx, vy
}
point_s points[4]

typedef struct line_s {
    byte x0, x1, y0, y1
}
line_s lines[4*NUM_POLYS]

#ram.end

#ram.org 0x590, 0x78
#define TILE_CACHE_SIZE (15*8)
byte tile_cache[TILE_CACHE_SIZE]
#ram.end

#ram.org 0x608, 0x1F8

#define DIRTY_FRAME_0   0x80
#define DIRTY_FRAME_1   0x40
#define CACHED_MASK     0x20
#define COUNT_MASK      0x1F

byte tile_status[TILES_WIDE*TILES_HIGH]
#ram.end
