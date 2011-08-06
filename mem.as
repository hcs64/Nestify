#define TILES_WIDE 24
#define TILES_HIGH 21

#define DLIST_SIZE 0x380

#ram.org 0x0, 0x30

pointer tmp_addr
byte    tmp_byte
byte    tmp_byte2
byte    tmp_byte3

// only used by NMI after init
shared byte _ppu_ctl0, _ppu_ctl1

// only set by NMI after init
shared byte _joypad0

// pattern table high bytes
shared byte this_frame_hi
shared byte other_frame_hi

// tile status bits
byte this_frame_mask
byte other_frame_mask

#ram.end

#ram.org 0xD1, 0x2f
byte    zp_writer[7]    //      stx $2006 ; sty $2006 ; lda #
byte zp_immed_0[5]      // NN ; sta $2007 ; lda #
byte zp_immed_1[5]      // NN ; sta $2007 ; lda #
byte zp_immed_2[5]      // NN ; sta $2007 ; lda #
byte zp_immed_3[5]      // NN ; sta $2007 ; lda #
byte zp_immed_4[5]      // NN ; sta $2007 ; lda #
byte zp_immed_5[5]      // NN ; sta $2007 ; lda #
byte zp_immed_6[5]      // NN ; sta $2007 ; lda #
byte zp_immed_7[5]      // NN ; sta $2007 ; rts

#ram.end

#ram.org 0x200, 0x200

#define DIRTY_FRAME_0   0x80
#define DIRTY_FRAME_1   0x40
#define TILE_PRIMS      0x1F

byte tile_status[TILES_WIDE*TILES_HIGH]

#ram.end

#ram.org 0x400, 0x400

byte dlist_0[DLIST_SIZE]
byte dlist_wrap_jmp[3]

byte dlist_start_jmp    // trampoline
word dlist_start
word dlist_next_start

#ram.end
