#ifndef EVAL_H
#define EVAL_H

#include "board.h"
#include <stdint.h>

#define INF 99999999

#define CHECKMATE -1000000
#define MATED -CHECKMATE
#define STALEMATE 0
#define PAWN_VALUE 100
#define KNIGHT_VALUE 325
#define ROOK_VALUE 500
#define BISHOP_VALUE 325
#define QUEEN_VALUE 1000
#define KING_VALUE 20000

#define MVVLVA_MUL 100

void init_eval(void);
int mat_val(enum Piece p);
int piece_val(enum Piece p);
int mg_pst_val(enum Piece p, int sq);
int eg_pst_val(enum Piece p, int sq);
void eval_board(struct Board *b, int *mg, int *eg);
int eval_position(struct Board *b);

bool is_endgame(struct Board *b);

int eval_move(Move m);

#endif /* EVAL_H */
