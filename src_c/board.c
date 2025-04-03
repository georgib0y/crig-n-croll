#include "board.h"
#include "eval.h"
#include "hashing.h"
#include "magic.h"
#include "movegen.h"
#include "util.h"
#include <string.h>

struct Board default_board(void) {
  struct Board b = {.pieces =
                        {
                            0x000000000000FF00, // wp 0
                            0x00FF000000000000, // bp 1
                            0x0000000000000042, // wn 2
                            0x4200000000000000, // bn 3
                            0x0000000000000081, // wr 4
                            0x8100000000000000, // br 5
                            0x0000000000000024, // wb 6
                            0x2400000000000000, // bb 7
                            0x0000000000000008, // wq 8
                            0x0800000000000000, // bq 9
                            0x0000000000000010, // wk 10
                            0x1000000000000000, // bk 11
                        },
                    .util =
                        {
                            0x000000000000FFFF, // white
                            0xFFFF000000000000, // black
                            0xFFFF00000000FFFF, // all
                        },
                    .ctm = WHITE,
                    .castling = 0xFF,
                    .halfmove = 0,
                    .ep = 64};
#ifdef HASHING
  b.hash = hash_board(&b);
#endif

#ifdef EVAL
  int mg, eg;
  eval_board(&b, &mg, &eg);
  b.mg_val = mg;
  b.eg_val = eg;
#endif

  return b;
}

enum Piece get_piece(struct Board *b, int sq) {
  BB mask = (BB)1 << sq;
  for (enum Piece p = PAWN_W; p < NONE; p++) {
    BB piece = b->pieces[p] & mask;
    if (piece) {
      return p;
    }
  }

  return NONE;
}

inline bool is_rook_like(enum Piece p) {
  return p == ROOK_W || p == ROOK_B || p == QUEEN_W || p == QUEEN_B;
}

inline bool is_bishop_like(enum Piece p) {
  return p == BISHOP_W || p == BISHOP_B || p == QUEEN_W || p == QUEEN_B;
}

// checks that the 2nd lsb (kingside) is set, shifts castle state down 2bits if
// white
inline bool can_kingside(struct Board *b) {
  return (b->castling >> (2 - 2 * b->ctm)) & 0x2; // 0b10
}

// checks that the lsb (queenside) is set, shifts castle state down 2bits if
// white
inline bool can_queenside(struct Board *b) {
  return (b->castling >> (2 - 2 * b->ctm)) & 1;
}

BB least_attacker_of_sq(struct Board *b, int sq, enum Piece *p,
                        enum Colour attacker) {
  BB bb;

  return 0;
}

BB attackers_of_sq(struct Board *b, int sq, enum Colour attackers) {
  BB atts = 0;

  // add pawn attacks, need to get the inverted pawn attacsk for the attacking
  // colour as we are working backwards from sq
  atts |= pawn_attack_bb(sq, !attackers) & b->pieces[PAWN_W + attackers];
  atts |= knight_attack_bb(sq) & b->pieces[KNIGHT_W + attackers];
  atts |= king_move_bb(sq) & b->pieces[KING_W + attackers];

  BB rook_queens =
      b->pieces[ROOK_W + attackers] | b->pieces[QUEEN_W + attackers];
  atts |= lookup_rook(b->util[ALL], sq) & rook_queens;
  BB bishop_queens =
      b->pieces[BISHOP_W + attackers] | b->pieces[QUEEN_W + attackers];
  atts |= lookup_bishop(b->util[ALL], sq) & bishop_queens;

  return atts;
}

bool is_in_check(struct Board *b) {
  int king_sq = lsb_idx(b->pieces[KING_W + b->ctm]);
  return attackers_of_sq(b, king_sq, !b->ctm);
}

static void set_castle_state(struct Board *b, enum Piece p, int from, int to) {
  // WKINGSIDE 0b1000
  if ((p == KING_W || from == 7 || to == 7) && b->castling & 0x8) {
    b->castling &= 0x7; // 0b0111
  }

  // WQUEENSIDE 0b100
  if ((p == KING_W || from == 0 || to == 0) && b->castling & 0x4) {
    b->castling &= 0xB; // 0b1011
  }

  // BKINGSIDE 0b10
  if ((p == KING_B || from == 63 || to == 63) && b->castling & 0x2) {
    b->castling &= 0xD; // 0b1101
  }

  // BQUEENSIDE 0b1
  if ((p == KING_B || from == 56 || to == 56) && b->castling & 0x1) {
    b->castling &= 0xE; // 0b1110
  }
}

static void apply_quiet(struct Board *b, enum Piece p) {
  b->halfmove *= (p >= KNIGHT_W);
}

static void apply_double(struct Board *b, int to) {
  b->ep = to - 8 + (b->ctm * 16);
  b->halfmove = 0;
}

static void apply_cap(struct Board *b, int to, enum Piece xpiece) {
  b->pieces[xpiece] ^= SQUARE(to);
  b->util[!b->ctm] ^= SQUARE(to);
  b->util[ALL] ^= SQUARE(to);
}

static void apply_castle(struct Board *b, enum Colour c, int from, int to) {
  BB from_to = SQUARE(from) | SQUARE(to);
  b->pieces[ROOK_W + c] ^= from_to;
  b->util[c] ^= from_to;
  b->util[ALL] ^= from_to;
}

static void apply_promo(struct Board *b, enum Piece xpiece, int to) {
  // toggle pawn off and toggle the promo on
  b->pieces[b->ctm] ^= SQUARE(to);
  b->pieces[xpiece] ^= SQUARE(to);

  b->halfmove = 0;
}

static void apply_promo_cap(struct Board *b, enum MoveType mt,
                            enum Piece xpiece, int to) {
  BB to_sq = SQUARE(to);
  // N_PROMO_CAP (8) - 7 = [1], [1] * 2 + b.colour_to_move == 2 or 3 (knight
  // idx)
  // R_PROMO_CAP (9) - 7 = [2], [2] * 2 + b.colour_to_move == 4 or 5 (rook idx)
  // etc

  enum Piece promo_p = (mt - 7) * 2 + b->ctm;

  // toggle captured piece
  b->pieces[xpiece] ^= to_sq;
  b->util[!b->ctm] ^= to_sq;

  // retoggle piece (as its been replaces by the capturer)
  b->util[ALL] ^= to_sq;
  // toggle pawn off
  b->pieces[b->ctm] ^= to_sq;
  // toggle promo on
  b->pieces[promo_p] ^= to_sq;

  b->halfmove = 0;
}

static void apply_ep(struct Board *b, int to) {
  int ep = to - 8 + (b->ctm * 16);

  // toggle capture pawn off
  b->pieces[!b->ctm] ^= SQUARE(ep);
  b->util[!b->ctm] ^= SQUARE(ep);
  b->util[ALL] ^= SQUARE(ep);

  b->halfmove = 0;
}

static void apply_move(struct Board *b, int to, enum Piece piece,
                       enum Piece xpiece, enum MoveType mt) {
  switch (mt) {
  case QUIET:
    apply_quiet(b, piece);
    break;
  case DOUBLE:
    apply_double(b, to);
    break;
  case CAP:
    apply_cap(b, to, xpiece);
    break;
  case WKINGSIDE:
    apply_castle(b, WHITE, 7, 5);
    break;
  case WQUEENSIDE:
    apply_castle(b, WHITE, 0, 3);
    break;
  case BKINGSIDE:
    apply_castle(b, BLACK, 63, 61);
    break;
  case BQUEENSIDE:
    apply_castle(b, BLACK, 56, 59);
    break;
  case PROMO:
    apply_promo(b, xpiece, to);
    break;
  case NPROMOCAP:
  case RPROMOCAP:
  case BPROMOCAP:
  case QPROMOCAP:
    apply_promo_cap(b, mt, xpiece, to);
    break;
  case EP:
    apply_ep(b, to);
  }
}

static inline void hash_change(struct Board *b, enum MoveType mt,
                               enum Piece piece, enum Piece xpiece, int from,
                               int to) {
  switch (mt) {
  case CAP:
    b->hash ^= hash_piece(xpiece, to);
    break;
  case WKINGSIDE:
    b->hash ^= hash_piece(ROOK_W, 7) ^ hash_piece(ROOK_W, 5);
    break;
  case WQUEENSIDE:
    b->hash ^= hash_piece(ROOK_W, 0) ^ hash_piece(ROOK_W, 3);
    break;
  case BKINGSIDE:
    b->hash ^= hash_piece(ROOK_B, 63) ^ hash_piece(ROOK_B, 61);
    break;
  case BQUEENSIDE:
    b->hash ^= hash_piece(ROOK_B, 56) ^ hash_piece(ROOK_B, 59);
    break;
  case PROMO:
    b->hash ^= hash_piece(piece, to) ^ hash_piece(xpiece, to);
    break;
  case NPROMOCAP:
    b->hash ^= hash_piece(piece, to) ^ hash_piece(xpiece, to) ^
               hash_piece(KNIGHT_W + b->ctm, to);
    break;
  case RPROMOCAP:
    b->hash ^= hash_piece(piece, to) ^ hash_piece(xpiece, to) ^
               hash_piece(ROOK_W + b->ctm, to);
    break;
  case BPROMOCAP:
    b->hash ^= hash_piece(piece, to) ^ hash_piece(xpiece, to) ^
               hash_piece(BISHOP_W + b->ctm, to);
    break;
  case QPROMOCAP:
    b->hash ^= hash_piece(piece, to) ^ hash_piece(xpiece, to) ^
               hash_piece(QUEEN_W + b->ctm, to);
    break;
  case EP: {
    int ep = to - 8 + (b->ctm * 16);
    b->hash ^= hash_piece((enum Piece) !b->ctm, ep);
    break;
  }
  default:
    break;
  }
}

static inline void add_piece_val(struct Board *b, enum Piece p, int sq) {
  int32_t mat = mat_val(p);
  b->mg_val += mat + mg_pst_val(p, sq);
  b->eg_val += mat + eg_pst_val(p, sq);
}

static inline void rm_piece_val(struct Board *b, enum Piece p, int sq) {
  int32_t mat = mat_val(p);
  b->mg_val -= mat + mg_pst_val(p, sq);
  b->eg_val -= mat + eg_pst_val(p, sq);
}

static inline void val_change(struct Board *b, enum MoveType mt,
                              enum Piece piece, enum Piece xpiece, int from,
                              int to) {
  switch (mt) {
  case CAP:
    rm_piece_val(b, xpiece, to);
    break;
  case WKINGSIDE:
    add_piece_val(b, ROOK_W, 5);
    rm_piece_val(b, ROOK_W, 7);
    break;
  case WQUEENSIDE:
    add_piece_val(b, ROOK_W, 3);
    rm_piece_val(b, ROOK_W, 0);
    break;
  case BKINGSIDE:
    add_piece_val(b, ROOK_B, 61);
    rm_piece_val(b, ROOK_B, 63);
    break;
  case BQUEENSIDE:
    add_piece_val(b, ROOK_B, 59);
    rm_piece_val(b, ROOK_B, 56);
    break;
  case PROMO:
    rm_piece_val(b, piece, to);
    add_piece_val(b, xpiece, to);
    break;
  case NPROMOCAP:
    rm_piece_val(b, piece, to);
    rm_piece_val(b, xpiece, to);
    add_piece_val(b, KNIGHT_W + b->ctm, to);
    break;
  case RPROMOCAP:
    rm_piece_val(b, piece, to);
    rm_piece_val(b, xpiece, to);
    add_piece_val(b, ROOK_W + b->ctm, to);
    break;
  case BPROMOCAP:
    rm_piece_val(b, piece, to);
    rm_piece_val(b, xpiece, to);
    add_piece_val(b, BISHOP_W + b->ctm, to);
    break;
  case QPROMOCAP:
    rm_piece_val(b, piece, to);
    rm_piece_val(b, xpiece, to);
    add_piece_val(b, QUEEN_W + b->ctm, to);
    break;
  case EP: {
    int ep = to - 8 + (b->ctm * 16);
    rm_piece_val(b, (enum Piece) !b->ctm, ep);
  }
  default:
    return;
  }
}

void copy_make(struct Board *restrict src, struct Board *restrict dest,
               Move m) {
  memcpy(dest, src, sizeof(struct Board));
  int from = m_from(m), to = m_to(m);
  enum Piece piece = m_piece(m), xpiece = m_xpiece(m);
  enum MoveType mt = m_move_type(m);

  BB from_to = SQUARE(from) | SQUARE(to);

  // set the piece
  dest->pieces[piece] ^= from_to;
  dest->util[dest->ctm] ^= from_to;
  dest->util[ALL] ^= from_to;

  set_castle_state(dest, piece, from, to);

  dest->ep = 64;
  dest->halfmove++;

  apply_move(dest, to, piece, xpiece, mt);

#ifdef HASHING
  dest->hash ^= hash_piece(piece, from) ^ hash_piece(piece, to);
  hash_change(dest, mt, piece, xpiece, from, to);

  // out with the old ep and  castle state and in with the new
  dest->hash ^= hash_ep(src->ep) ^ hash_ep(dest->ep);
  /* if (src->castling != dest->castling) { */
  /*   LOGCASTLE(src->castling); */
  /*   LOGCASTLE(dest->castling); */
  /* } */

  dest->hash ^= hash_castling(src->castling) ^ hash_castling(dest->castling);
  dest->hash ^= hash_colour();
#endif

#ifdef EVAL
  add_piece_val(dest, piece, to);
  rm_piece_val(dest, piece, from);
  val_change(dest, mt, piece, xpiece, from, to);
#endif

  dest->ctm = !src->ctm;
}
