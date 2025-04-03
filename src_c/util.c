#include "util.h"
#include "board.h"
#include "eval.h"
#include "hashing.h"
#include "magic.h"
#include "movegen.h"
#include <stdlib.h>
#include <string.h>

static char *piece_names[] = {
    "PAWN_W", "PAWN_B",   "KNIGHT_W", "KNIGHT_B", "ROOK_W",
    "ROOK_B", "BISHOP_W", "BISHOP_B", "QUEEN_W",  "QUEEN_B",
    "KING_W", "KING_B",   "NONE",
};

char *piece_name(enum Piece p) { return piece_names[p]; }

static char *mt_names[] = {
    "QUIET",      "DOUBLE",     "CAP",   "WKINGSIDE", "BKINGSIDE",
    "WQUEENSIDE", "BQUEENSIDE", "PROMO", "NPROMOCAP", "RPROMOCAP",
    "BPROMOCAP",  "QPROMOCAP",  "EP",
};

char *movetype_name(enum MoveType mt) { return mt_names[mt]; }

static char BB_PIECE_NAMES[13] = {
    'P', 'p', 'N', 'n', 'R', 'r', 'B', 'b', 'Q', 'q', 'K', 'k', '.',
};

char piece_name_char(enum Piece p) { return BB_PIECE_NAMES[p]; }

void fprint_board(FILE *f, struct Board *b) {
  for (int i = 7; i >= 0; i--) {
    fprintf(f, "%d ", i + 1);
    for (int sq = i * 8; sq < (i + 1) * 8; sq++) {
      fprintf(f, " ");
      // print all pieces for a square to catch doubleups
      bool printed = false;
      for (enum Piece p = PAWN_W; p < NONE; p++) {
        if (b->pieces[p] & SQUARE(sq)) {
          fprintf(f, "%c", piece_name_char(p));
          printed = true;
        }
      }
      if (!printed) {
        fprintf(f, ".");
      }
      fprintf(f, " ");
    }
    fprintf(f, "\n");
  }
  fprintf(f, "\n   A  B  C  D  E  F  G  H\n");
}

void print_board(struct Board *b) { fprint_board(stdout, b); }

void fprint_bb(FILE *f, BB bb) {
  for (int i = 7; i >= 0; i--) {
    fprintf(f, "%d ", i + 1);
    for (int sq = i * 8; sq < (i + 1) * 8; sq++) {
      fprintf(f, " %c ", (bb & SQUARE(sq)) ? 'X' : '.');
    }
    fprintf(f, "\n");
  }
  fprintf(f, "\n   A  B  C  D  E  F  G  H\n");
}

void print_bb(BB bb) { fprint_bb(stdout, bb); }

void sq_name(char *dest, int sq) {
  char file = (sq % 8) + 'a', rank = (sq / 8) + '1';
  dest[0] = file;
  dest[1] = rank;
  dest[2] = '\0';
}

void fprint_move(FILE *f, Move m) {
  char from_sq[3] = "na", to_sq[3] = "na";
  if (0 <= m_from(m) && m_from(m) < 64) {
    sq_name(from_sq, m_from(m));
  }

  if (0 <= m_to(m) && m_to(m) < 64) {
    sq_name(to_sq, m_to(m));
  }

  fprintf(
      f,
      "from: %s (%d), to: %s (%d), piece: %s, xpeice: %s, movetype: %s {%d}\n",
      from_sq, m_from(m), to_sq, m_to(m), piece_name(m_piece(m)),
      piece_name(m_xpiece(m)), movetype_name(m_move_type(m)), m);
}

int sq_from_str(char *sq, char *sq_str) {
  if (strlen(sq_str) != 2) {
    LOG("invalid string len for sq str: %s (%ld)\n", sq_str, strlen(sq_str));
    return 1;
  }

  char file = sq_str[0], rank = sq_str[1];

  if (file < 'a' || file > 'h' || rank < '1' || rank > '8') {
    LOG("invalid sq str: %s\n", sq_str);
    return 1;
  }

  *sq = (rank - '1') * 8 + (file - 'a');
  return 0;
}

void fprint_castlestate(FILE *restrict f, CastleState cs) {
  if (!cs) {
    fprintf(f, "-\n");
    return;
  }

  if (cs & 0x8)
    fprintf(f, "K");
  if (cs & 0x4)
    fprintf(f, "Q");
  if (cs & 0x2)
    fprintf(f, "k");
  if (cs & 0x1)
    fprintf(f, "q");

  fprintf(f, "\n");
}

// TODO may need to account for ctm?
enum Piece promo_from_char(char promo) {
  if (promo <= PAWN_B || promo >= KING_W) {
    return NONE;
  }

  enum Piece p = NONE;
  for (p = KNIGHT_W; p <= KING_W || piece_name_char(p) != promo; p++)
    ;

  return p;
}

Move move_from_str(struct Board *b, char *move_str) {
  int len = strlen(move_str);

  if (len < 4) {
    LOG("invalid move (too long): %s\n", move_str);
    return NULL_MOVE;
  }

  char from, to, from_str[3], to_str[3];
  from_str[0] = move_str[0];
  from_str[1] = move_str[1];
  from_str[2] = '\0';

  to_str[0] = move_str[2];
  to_str[1] = move_str[3];
  to_str[2] = '\0';

  if (sq_from_str(&from, from_str)) {
    LOG("invalid move (bad from): %s\n", move_str);
    return NULL_MOVE;
  }

  strncpy(to_str, move_str + 2, 2);
  if (sq_from_str(&to, to_str)) {
    LOG("invalid move (bad to): %s\n", move_str);
    return NULL_MOVE;
  }

  enum Piece promo = NONE;
  if (len == 5) {
    promo = promo_from_char(move_str[4]);
    if (promo == NONE) {
      LOG("invalid move (bad promo): %s\n", move_str);
      return NULL_MOVE;
    }
  }

  enum Piece piece = get_piece(b, from);
  if (piece == NONE) {
    LOG("invalid move (bad from piece %s): %s\n", piece_name(piece), move_str);
    return NULL_MOVE;
  }

  enum MoveType mt = QUIET;

  // check for double push
  if (piece <= PAWN_B && abs(from - to) == 16) {
    mt = DOUBLE;
  }

  // check for castling
  if (piece >= KING_W && abs(from - to) == 2) {
    mt = ((from < to) ? WKINGSIDE : WQUEENSIDE) + b->ctm;
  }

  enum Piece xpiece = get_piece(b, to);
  if (xpiece != NONE && promo != NONE) {
    if (promo == KNIGHT_W || promo == KNIGHT_B)
      mt = NPROMOCAP;
    else if (promo == ROOK_W || promo == ROOK_B)
      mt = RPROMOCAP;
    else if (promo == BISHOP_W || promo == BISHOP_B)
      mt = BPROMOCAP;
    else if (promo == QUEEN_W || promo == QUEEN_B)
      mt = QPROMOCAP;
    else {
      LOG("invalid move (bad promo cap): %s\n", move_str);
      return NULL_MOVE;
    }
  }

  if (xpiece == NONE && promo != NONE) {
    mt = PROMO;
    xpiece = promo;
  }

  if (piece <= PAWN_B && to == b->ep) {
    mt = EP;
  }

  if (xpiece != NONE && promo == NONE) {
    mt = CAP;
  }

  return new_move(from, to, piece, xpiece, mt);
}

// dest must be at least 6 bytes if promo or 5 if not promo
void uci_from_move(char *dest, Move m) {
  char from[3], to[3];
  sq_name(from, m_from(m));
  sq_name(to, m_to(m));

  char *buf = stpncpy(dest, from, 2);
  buf = stpncpy(buf, to, 2);

  switch (m_move_type(m)) {
  case PROMO: {
    *buf = piece_name_char(m_xpiece(m));
    buf++;
    break;
  }
  case NPROMOCAP: {
    *buf = 'n';
    buf++;
    break;
  }
  case RPROMOCAP: {
    *buf = 'r';
    buf++;
    break;
  }
  case BPROMOCAP: {
    *buf = 'b';
    buf++;
    break;
  }
  case QPROMOCAP: {
    *buf = 'q';
    buf++;
    break;
  }
  default:
    break;
  }

  *buf = '\0';
}

void init(void) {
  // magics must be init before moves
  init_magics();
  init_moves();

#ifdef HASHING
  init_hashing();
#endif

#ifdef EVAL
  init_eval();
#endif
}
