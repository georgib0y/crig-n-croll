#ifndef MAGIC_H
#define MAGIC_H

#include "board.h"
#include "stdbool.h"

#define BISHOP_SHIFT 9
#define ROOK_SHIFT 12

// TODO see if storing a pointer to the array in this struct is different to
// looking up[sq][occ]. This approach might be useful if storing all BBs in the
// same array
struct SquareMagic {
  uint64_t magic;
  BB mask;
};

void init_magics(void);

uint64_t rmask(int sq);
uint64_t bmask(int sq);

BB lookup_bishop(BB occ, int sq);
BB lookup_bishop_xray(BB occ, BB blockers, int sq);
BB lookup_rook(BB occ, int sq);
BB lookup_rook_xray(BB occ, BB blockers, int sq);
BB lookup_queen(BB occ, int sq);

BB rook_mask(int sq);
BB bishop_mask(int sq);

void populate_move_table(BB move_table[], struct SquareMagic m, int sq,
                         int shift, bool is_bishop);

#endif /* MAGIC_H */
