#include "board.h"
#include "movegen.h"
#include <stdint.h>

#define Z_ARRAY_SIZE (12 * 64 + 1 + 16 + 8)

static uint64_t ZORBIST_ARRAY[Z_ARRAY_SIZE];

static uint64_t rand_state = 7697942984269075730ULL;

static uint64_t next_random(void) {
  rand_state ^= rand_state << 13;
  rand_state ^= rand_state >> 7;
  rand_state ^= rand_state << 17;
  return rand_state;
}

void init_hashing(void) {
  for (int i = 0; i < Z_ARRAY_SIZE; i++) {
    ZORBIST_ARRAY[i] = next_random();
  }
}

uint64_t hash_piece(enum Piece p, int sq) { return ZORBIST_ARRAY[p * 64 + sq]; }
uint64_t hash_colour(void) { return ZORBIST_ARRAY[768]; }
uint64_t hash_castling(CastleState cs) { return ZORBIST_ARRAY[769 + cs]; }
uint64_t hash_ep(int sq) { return ZORBIST_ARRAY[785 + (sq % 8)] * (sq < 64); }

uint64_t hash_board(struct Board *b) {
  uint64_t hash = 0;

  for (enum Piece p = PAWN_W; p <= KING_B; p++) {
    BB pieces = b->pieces[p];
    while (pieces) {
      hash ^= hash_piece(p, lsb_idx(pieces));
      pieces &= pieces - 1;
    }
  }

  if (b->ctm) {
    hash ^= hash_colour();
  }

  hash ^= hash_castling(b->castling);
  hash ^= hash_ep(b->ep);

  return hash;
}
