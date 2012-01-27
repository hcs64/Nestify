#define TILES_WIDE 24
#define TILES_HIGH 21
#define TILE_CACHE_ELEMENTS 64

#ram.org 0x0, 0x10

pointer tmp_addr
byte    tmp_byte
byte    tmp_byte2
byte    tmp_byte3

// only used by NMI after init
shared byte _ppu_ctl0, _ppu_ctl1
byte nmi_temp

// always set by NMI, use to check if ops could be interrupted
byte nmi_hit

word incomplete_vblanks
word complete_vblanks
word stuck_cnt
#ram.end

#ram.org 0x11, 0x60

dlist_addr_data:  // 0x11, 0x13, etc to 0x71
byte pad00

// tile status bits
byte this_frame_mask,       pad01
byte other_frame_mask,      pad02
byte count_mask_zp,         pad03
byte cur_nametable_page,    pad04

// small dlist stuff
byte dlist_next_cmd_read,   pad05
byte dlist_next_cmd_write,  pad06
byte dlist_cmd_end,         pad07

byte dlist_cycles_left0,    pad08
byte dlist_cycles_left1,    pad09
byte dlist_reset_cycles,    pad0a

byte dlist_cmd_copy0,       pad0b
byte dlist_cmd_copy1,       pad0c
byte dlist_orig_S,          pad0d

byte cmd_addr0,             pad0e
byte cmd_addr1,             pad0f
byte cmd_start,             pad10
byte cmd_cache_start,       pad11
byte cmd_lines,             pad12

byte last_cmd_cycles,       pad13

byte line_x0,               pad14
byte line_y0,               pad15
byte line_x1,               pad16
byte line_y1,               pad17

byte line_row,              pad18
byte line_iters,            pad19
byte line_x_block,          pad1a
byte line_block0,           pad1b
byte line_block1,           pad1c
byte line_err0,             pad1d
byte line_err1,             pad1e

byte head_poly,             pad1f
byte tail_poly,             pad20
byte pal_cur,               pad21
byte pal_dest,              pad22
byte pal_delay,             pad23
byte pal_timer,             pad24
byte rndx,                  pad25
byte rndy,                  pad26

#ram.end

#ram.org 0x71, 0x4D
// must be contiguous
word line_err_strt
word line_err_diag

byte cmd_byte[8]

byte tile_cache_list[TILE_CACHE_ELEMENTS]
byte tile_cache_free_ptr
#ram.end

#ram.org 0xD7, 0x29
byte zp_writer[1]   //                  lda #
byte zp_immed_0[5]  // NN ; sta $2007 ; lda #
byte zp_immed_1[5]  // NN ; sta $2007 ; lda #
byte zp_immed_2[5]  // NN ; sta $2007 ; lda #
byte zp_immed_3[5]  // NN ; sta $2007 ; lda #
byte zp_immed_4[5]  // NN ; sta $2007 ; lda #
byte zp_immed_5[5]  // NN ; sta $2007 ; lda #
byte zp_immed_6[5]  // NN ; sta $2007 ; lda #
byte zp_immed_7[5]  // NN ; sta $2007 ; rts

#ram.end

#ram.org 0x100, 0x100
byte dlist[0x60]
dlist_end:
byte dlist_wrap[2]

// stack
byte stack[0x20]
stack_end:

// 
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

#ram.org 0x200, 0x200

byte tile_cache_dirty_range_0[0x40]
byte dlist_bitmap_0[0x60]   // 0, 1
byte dlist_bitmap_1[0x60]   // 2, 3
byte tile_cache_dirty_range_1[0x40]
byte dlist_bitmap_2[0x60]   // 4, 5
byte dlist_bitmap_3[0x60]   // 6, 7

#ram.end

#ram.org 0x400, 0x200
byte tile_cache[TILE_CACHE_ELEMENTS*8]
#ram.end

#ram.org 0x608, 0x1F8

#define CACHED_MASK     0x80
#define DIRTY_FRAME_0   0x40
#define DIRTY_FRAME_1   0x20
#define COUNT_MASK      0x1F
#define CACHE_LINE_MASK 0x7F

byte tile_status[TILES_WIDE*TILES_HIGH]
#ram.end
