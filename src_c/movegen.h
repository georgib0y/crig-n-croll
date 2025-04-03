#ifndef MOVEGEN_H
#define MOVEGEN_H

#include "board.h"
#include <stdbool.h>
#include <stdint.h>

#define MAX_MOVES 200

enum MoveType {
  QUIET,
  DOUBLE,
  CAP,
  WKINGSIDE,
  BKINGSIDE,
  WQUEENSIDE,
  BQUEENSIDE,
  PROMO,
  NPROMOCAP,
  RPROMOCAP,
  BPROMOCAP,
  QPROMOCAP,
  EP,
};

BB pawn_attack_bb(int sq, enum Colour ctm);
BB knight_attack_bb(int sq);
BB king_move_bb(int sq);

int lsb_idx(BB bb);

typedef uint32_t Move;

Move new_move(int from, int to, int piece, int xpiece, enum MoveType mt);

int m_from(Move m);
int m_to(Move m);
enum Piece m_piece(Move m);
enum Piece m_xpiece(Move m);
enum MoveType m_move_type(Move m);
bool m_is_promo(Move m);
bool m_is_cap(Move m);

struct MoveList {
  Move moves[MAX_MOVES];
  int scores[MAX_MOVES];
  int count;
};

struct MoveList new_move_list(void);
void score_moves(struct MoveList *ml);
bool next_move(struct MoveList *ml, Move *m);
bool next_q_move(struct MoveList *ml, Move *m);

void init_moves(void);

void gen_moves(struct Board *b, struct MoveList *ml, bool checked);
void gen_q_moves(struct Board *b, struct MoveList *ml);

bool is_legal_move(struct Board *b, Move m, bool checked);

#endif /* MOVEGEN_H */
