#ifndef BOARD_H
#define BOARD_H

#include <stdbool.h>
#include <stdint.h>

#define NUM__PIECES 4
#define NULL_MOVE 0

typedef uint64_t BB;
typedef BB File;
typedef BB Rank;
typedef uint8_t CastleState;
typedef uint32_t Move;

#define SQUARE(sq) ((BB)1 << (sq))

#define FA 0x0101010101010101ULL
#define FB 0x0202020202020202ULL
#define FC 0x0404040404040404ULL
#define FD 0x0808080808080808ULL
#define FE 0x1010101010101010ULL
#define FF 0x2020202020202020ULL
#define FG 0x4040404040404040ULL
#define FH 0x8080808080808080ULL

#define R1 0x00000000000000FFULL
#define R2 0x000000000000FF00ULL
#define R3 0x0000000000FF0000ULL
#define R4 0x00000000FF000000ULL
#define R5 0x000000FF00000000ULL
#define R6 0x0000FF0000000000ULL
#define R7 0x00FF000000000000ULL
#define R8 0xFF00000000000000ULL

enum Colour { WHITE, BLACK };

enum Piece {
  PAWN_W,
  PAWN_B,
  KNIGHT_W,
  KNIGHT_B,
  ROOK_W,
  ROOK_B,
  BISHOP_W,
  BISHOP_B,
  QUEEN_W,
  QUEEN_B,
  KING_W,
  KING_B,
  NONE,
};

enum UtilBB { ALL_W, ALL_B, ALL };

struct Board {
  BB pieces[12];
  BB util[3];
  enum Colour ctm;
  CastleState castling;
  char ep, halfmove;
  uint64_t hash;
  int32_t mg_val;
  int32_t eg_val;
};

enum Piece get_piece(struct Board *b, int sq);
bool is_rook_like(enum Piece p);
bool is_bishop_like(enum Piece p);

File sq_file(int sq);
Rank sq_rank(int sq);

struct Board default_board(void);
int board_from_fen(struct Board *b, const char *fen);

void copy_make(struct Board *src, struct Board *dest, Move m);

BB attackers_of_sq(struct Board *b, int sq, enum Colour attackers);
bool is_in_check(struct Board *b);

bool can_kingside(struct Board *b);
bool can_queenside(struct Board *b);

#endif /* BOARD_H */
