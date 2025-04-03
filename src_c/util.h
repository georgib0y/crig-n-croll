#ifndef UTIL_H
#define UTIL_H

#include "board.h"
#include "movegen.h"
#include <stdio.h>

#define NOOP (void)0

#ifdef DEBUG
#define LOG(...)                                                               \
  fprintf(stderr, "[%s %d] ", __FILE__, __LINE__);                             \
  fprintf(stderr, __VA_ARGS__)
#define LOGBB(bb)                                                              \
  fprintf(stderr, "[%s %d]\n", __FILE__, __LINE__);                            \
  fprint_bb(stderr, bb)
#define LOGMOVE(m)                                                             \
  fprintf(stderr, "[%s %d] ", __FILE__, __LINE__);                             \
  fprint_move(stderr, m)
#define LOGMOVE(m)                                                             \
  fprintf(stderr, "[%s %d] ", __FILE__, __LINE__);                             \
  fprint_move(stderr, m)
#define LOGBOARD(b)                                                            \
  fprintf(stderr, "[%s %d]\n", __FILE__, __LINE__);                            \
  fprint_board(stderr, b)
#define LOGCASTLE(cs)                                                          \
  fprintf(stderr, "[%s %d]\n", __FILE__, __LINE__);                            \
  fprint_castlestate(stderr, cs)
#else
#define LOG(...) NOOP
#define LOGBB(bb) NOOP
#define LOGMOVE(m) NOOP
#define LOGBOARD(b) NOOP
#define LOGCASTLE(cs) NOOP
#endif

char *piece_name(enum Piece p);
char *movetype_name(enum MoveType mt);
char piece_name_char(enum Piece p);

void fprint_board(FILE *restrict f, struct Board *b);
void print_board(struct Board *b);

void fprint_bb(FILE *restrict f, BB bb);
void print_bb(BB bb);

void fprint_move(FILE *restrict f, Move m);

void fprint_castlestate(FILE *restrict f, CastleState cs);

int sq_from_str(char *sq, char *sq_str);
Move move_from_str(struct Board *b, char *move_str);
void uci_from_move(char *dest, Move m);

void init(void);

#endif /* UTIL_H */
