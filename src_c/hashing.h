#ifndef HASHING_H
#define HASHING_H

#include "board.h"
#include <stdint.h>

void init_hashing(void);

uint64_t hash_piece(enum Piece p, int sq);
uint64_t hash_colour(void);
uint64_t hash_castling(CastleState cs);
uint64_t hash_ep(int sq);

uint64_t hash_board(struct Board *b);
#endif /* HASHING_H */
