#define TILES_WIDE 24
#define TILES_HIGH 21

#ram.org 0x0, 0x40

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

// small dlist stuff
word dlist_cycles_left
shared byte dlist_count

byte dlist_start_jmp
word dlist_start
word dlist_next_byte

#define MAX_DLISTS 4
#define MAX_DLISTS_MOD_MASK %110

word dlists[MAX_DLISTS]
byte dlist_read_idx
byte dlist_write_idx

word cmd_addr
byte cmd_start
byte cmd_lines
byte cmd_op
byte cmd_byte[8]

// only check_for_space_and_cycles() uses these
byte cmd_size
byte cmd_cycles // reused for operation line range
#ram.end

#ram.org 0x40, 0x20
// 0x40
shared byte frame_counter
// 0x41
byte last_frame_time
// 0x42
byte wasted_nmis
// 0x43
byte total_dlists
// 0x44
word stuck_cnt
#ram.end

#ram.org 0x60, 0x20
// if we need space this can be put out of zero page with no extra cycle cost as
// long as it doesn't cross a page boundary
byte flip_nametable[0x20]
#ram.end

#ram.org 0x80, 0x11
byte test_angle
byte test_speed

byte test_x0
byte test_y0
byte test_x1
byte test_y1

byte test_byte
byte test_iters
byte test_x_block
word test_err
word test_err_strt
word test_err_diag
word test_block
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

#ram.org 0x200, 0x1F8

#define DIRTY_FRAME_0   0x80
#define DIRTY_FRAME_1   0x40
#define COUNT_MASK      0x1F

byte tile_status[TILES_WIDE*TILES_HIGH]
#ram.end

#ram.org 0x400, 0x383

#define DLIST_SIZE 0x380
#define DLIST_WORST_CASE_SIZE 0x37C // -4

byte dlist_0[DLIST_SIZE]
#define DLIST_LAST_CMD_START (dlist_0+DLIST_WORST_CASE_SIZE)
byte dlist_wrap_jmp[3]

#ram.end
