#include "movegen.h"
#include "board.h"
#include "eval.h"
#include "magic.h"
#include "util.h"
#include <stdbool.h>
#include <stdint.h>

#define NUM_PROMO_PIECES 4

#define NO_SQUARES 0
#define ALL_SQUARES 0xFFFFFFFFFFFFFFFFULL

const enum MoveType PROMO_CAP_MTS[4] = {NPROMOCAP, RPROMOCAP, BPROMOCAP,
                                        QPROMOCAP};

const enum Piece PROMO_PIECES_W[4] = {KNIGHT_W, ROOK_W, BISHOP_W, QUEEN_W};
const enum Piece PROMO_PIECES_B[4] = {KNIGHT_B, ROOK_B, BISHOP_B, QUEEN_B};

const File FILES[8] = {FA, FB, FC, FD, FE, FF, FG, FH};

const Rank RANKS[8] = {R1, R2, R3, R4, R5, R6, R7, R8};

inline int lsb_idx(BB bb) { return __builtin_ctzl(bb); }

static BB KNIGHT_MOVE_TABLE[64];

void init_knight_move_table(void) {
  for (int i = 0; i < 64; i++) {
    BB bb = 0;
    bb |= (SQUARE(i) & ~FA & ~FB) << 6;
    bb |= (SQUARE(i) & ~FA) << 15;
    bb |= (SQUARE(i) & ~FH) << 17;
    bb |= (SQUARE(i) & ~FG & ~FH) << 10;
    bb |= (SQUARE(i) & ~FH & ~FG) >> 6;
    bb |= (SQUARE(i) & ~FH) >> 15;
    bb |= (SQUARE(i) & ~FA) >> 17;
    bb |= (SQUARE(i) & ~FA & ~FB) >> 10;

    KNIGHT_MOVE_TABLE[i] = bb;
  }
}

BB knight_attack_bb(int sq) { return KNIGHT_MOVE_TABLE[sq]; }

static BB KING_MOVE_TABLE[64];

void init_king_move_table(void) {
  for (int i = 0; i < 64; i++) {
    BB bb = 0;
    BB k_clear_a = SQUARE(i) & ~FA;
    BB k_clear_h = SQUARE(i) & ~FH;

    bb |= SQUARE(i) << 8;
    bb |= SQUARE(i) >> 8;
    bb |= k_clear_a << 7;
    bb |= k_clear_a >> 1;
    bb |= k_clear_a >> 9;
    bb |= k_clear_h << 9;
    bb |= k_clear_h << 1;
    bb |= k_clear_h >> 7;

    KING_MOVE_TABLE[i] = bb;
  }
}

BB king_move_bb(int sq) { return KING_MOVE_TABLE[sq]; }

static BB PAWN_ATTACK_TABLE[128];

void init_pawn_attacks(void) {
  for (int i = 0; i < 64; i++) {
    BB sq = SQUARE(i);

    // white
    if (sq & ~R8) {
      PAWN_ATTACK_TABLE[i] = (sq & ~FA) << 7 | (sq & ~FH) << 9;
    }

    // black
    if (sq & ~R1) {
      PAWN_ATTACK_TABLE[i + 64] = (sq & ~FH) >> 7 | (sq & ~FA) >> 9;
    }
  }
}

BB pawn_attack_bb(int sq, enum Colour ctm) {
  return PAWN_ATTACK_TABLE[sq + (ctm * 64)];
}

void init_moves(void) {
  init_pawn_attacks();
  init_knight_move_table();
  init_king_move_table();
}

Move new_move(int from, int to, int piece, int xpiece, enum MoveType mt) {
  return from << 18 | to << 12 | piece << 8 | xpiece << 4 | mt;
}

inline int m_from(Move m) { return m >> 18; }
inline int m_to(Move m) { return (m >> 12) & 0x3F; }
inline enum Piece m_piece(Move m) { return (m >> 8) & 0xF; }
inline enum Piece m_xpiece(Move m) { return (m >> 4) & 0xF; }
inline enum MoveType m_move_type(Move m) { return m & 0xF; }
inline bool m_is_promo(Move m) {
  enum MoveType mt = m_move_type(m);
  return PROMO <= mt && mt <= QPROMOCAP;
}

inline bool m_is_cap(Move m) {
  enum MoveType mt = m_move_type(m);
  return mt == CAP || mt >= NPROMOCAP;
}

inline struct MoveList new_move_list(void) {
  return (struct MoveList){.count = 0};
}

void score_moves(struct MoveList *ml) {
  for (int i = 0; i < ml->count; i++) {
    ml->scores[i] = eval_move(ml->moves[i]);
  }
}

bool next_move(struct MoveList *ml, Move *m) {
  int idx = -INF, best_score = -INF;

  for (int i = 0; i < ml->count; i++) {
    if (ml->scores[i] > best_score) {
      idx = i;
      best_score = ml->scores[i];
    }
  }

  if (idx == -INF) {
    return false;
  }

  *m = ml->moves[idx];
  ml->scores[idx] = -INF; // set this move to low so that it isn't picked again

  return true;
}

// the same as next_move() but doesnt select bad trades
bool next_q_move(struct MoveList *ml, Move *m) {
  int idx = -INF, best_score = -INF;

  for (int i = 0; i < ml->count; i++) {
    if (ml->scores[i] > MVVLVA_MUL && ml->scores[i] > best_score) {
      idx = i;
      best_score = ml->scores[i];
    }
  }

  if (idx == -INF) {
    return false;
  }

  *m = ml->moves[idx];
  ml->scores[idx] = -INF; // set this move to low so that it isn't picked again

  return true;
}

void add_move(struct MoveList *ml, Move m) { ml->moves[ml->count++] = m; }

void add_pawn_moves_quiet(struct MoveList *ml, BB pawns, enum Piece piece,
                          int to_offset, enum Piece promo, enum MoveType mt) {
  while (pawns) {
    int from = lsb_idx(pawns);
    pawns &= pawns - 1;
    add_move(ml, new_move(from, from + to_offset, piece, promo, mt));
  }
}

void add_pawn_moves_cap(struct MoveList *ml, struct Board *b, BB pawns,
                        enum Piece piece, int to_offset, enum MoveType mt) {
  while (pawns) {
    int from = lsb_idx(pawns);
    int to = from + to_offset;
    enum Piece xpiece = get_piece(b, to);
    pawns &= pawns - 1;
    add_move(ml, new_move(from, from + to_offset, piece, xpiece, mt));
  }
}

void wpawn_quiet(struct Board *b, struct MoveList *ml, BB pin_sqs,
                 BB target_sqs) {
  BB pawns = b->pieces[PAWN_W] & ~pin_sqs;
  BB occ = b->util[ALL] | ~target_sqs;
  BB quiet = pawns & ~(occ >> 8);

  BB push = quiet & ~R7;
  add_pawn_moves_quiet(ml, push, PAWN_W, 8, NONE, QUIET);

  BB double_push = (pawns & R2) & ~(occ >> 16) & ~(b->util[ALL] >> 8);
  add_pawn_moves_quiet(ml, double_push, PAWN_W, 16, NONE, DOUBLE);

  BB promo = quiet & R7;
  if (promo) {
    for (int i = 0; i < NUM_PROMO_PIECES; i++) {
      add_pawn_moves_quiet(ml, promo, PAWN_W, 8, PROMO_PIECES_W[i], PROMO);
    }
  }
}

void wpawn_attack(struct Board *b, struct MoveList *ml, BB pin_sqs,
                  BB target_sqs) {
  BB pawns = b->pieces[PAWN_W] & ~pin_sqs;
  BB opp = b->util[BLACK] & target_sqs;

  BB att_left = (pawns & ~FA) & (opp >> 7);
  BB att_right = (pawns & ~FH) & (opp >> 9);

  // up left
  add_pawn_moves_cap(ml, b, att_left & ~R7, PAWN_W, 7, CAP);
  // up right
  add_pawn_moves_cap(ml, b, att_right & ~R7, PAWN_W, 9, CAP);

  BB att_left_promo = att_left & R7;
  if (att_left_promo) {
    for (int i = 0; i < NUM_PROMO_PIECES; i++) {
      add_pawn_moves_cap(ml, b, att_left_promo, PAWN_W, 7, PROMO_CAP_MTS[i]);
    }
  }

  BB att_right_promo = att_right & R7;
  if (att_right_promo) {
    for (int i = 0; i < NUM_PROMO_PIECES; i++) {
      add_pawn_moves_cap(ml, b, att_right_promo, PAWN_W, 9, PROMO_CAP_MTS[i]);
    }
  }
}

void wpawn_ep(struct Board *b, struct MoveList *ml, BB pin_sqs, BB target_sqs) {
  if (b->ep >= 64) {
    return;
  }

  BB pawns = b->pieces[PAWN_W] & ~pin_sqs;
  BB opp = b->util[BLACK] & target_sqs;

  // back right
  if (SQUARE(b->ep) & ((pawns & ~FA) << 7) & opp << 8) {
    add_pawn_moves_cap(ml, b, SQUARE(b->ep) >> 7, PAWN_W, 7, EP);
  }

  if (SQUARE(b->ep) & ((pawns & ~FH) << 9) & opp << 8) {
    add_pawn_moves_cap(ml, b, SQUARE(b->ep) >> 9, PAWN_W, 9, EP);
  }
}

void bpawn_quiet(struct Board *b, struct MoveList *ml, BB pin_sqs,
                 BB target_sqs) {
  BB pawns = b->pieces[PAWN_B] & ~pin_sqs;
  BB occ = b->util[ALL] | ~target_sqs;
  BB quiet = pawns & ~(occ << 8);

  BB push = quiet & ~R2;
  add_pawn_moves_quiet(ml, push, PAWN_B, -8, NONE, QUIET);

  BB double_push = (pawns & R7) & ~(occ << 16) & ~(b->util[ALL] << 8);
  add_pawn_moves_quiet(ml, double_push, PAWN_B, -16, NONE, DOUBLE);

  BB promo = quiet & R2;
  if (promo) {
    for (int i = 0; i < NUM_PROMO_PIECES; i++) {
      add_pawn_moves_quiet(ml, promo, PAWN_B, -8, PROMO_PIECES_B[i], PROMO);
    }
  }
}

void bpawn_attack(struct Board *b, struct MoveList *ml, BB pin_sqs,
                  BB target_sqs) {
  BB pawns = b->pieces[PAWN_B] & ~pin_sqs;
  BB opp = b->util[WHITE] & target_sqs;

  BB att_left = (pawns & ~FA) & (opp << 9);
  BB att_right = (pawns & ~FH) & (opp << 7);

  // down left
  add_pawn_moves_cap(ml, b, att_left & ~R2, PAWN_B, -9, CAP);
  // up right
  add_pawn_moves_cap(ml, b, att_right & ~R2, PAWN_B, -7, CAP);

  BB att_left_promo = att_left & R2;
  if (att_left_promo) {
    for (int i = 0; i < NUM_PROMO_PIECES; i++) {
      add_pawn_moves_cap(ml, b, att_left_promo, PAWN_B, -9, PROMO_CAP_MTS[i]);
    }
  }

  BB att_right_promo = att_right & R2;
  if (att_right_promo) {
    for (int i = 0; i < NUM_PROMO_PIECES; i++) {
      add_pawn_moves_cap(ml, b, att_right_promo, PAWN_B, -7, PROMO_CAP_MTS[i]);
    }
  }
}

void bpawn_ep(struct Board *b, struct MoveList *ml, BB pin_sqs, BB target_sqs) {
  if (b->ep >= 64) {
    return;
  }

  BB pawns = b->pieces[PAWN_B] & ~pin_sqs;
  BB opp = b->util[WHITE] & target_sqs;

  // down left
  if (SQUARE(b->ep) & ((pawns & ~FA) >> 9) & opp >> 8) {
    add_pawn_moves_cap(ml, b, SQUARE(b->ep) << 9, PAWN_B, -9, EP);
  }

  // down right
  if (SQUARE(b->ep) & ((pawns & ~FH) >> 7) & opp >> 8) {
    add_pawn_moves_cap(ml, b, SQUARE(b->ep) << 7, PAWN_B, -7, EP);
  }
}

void add_moves(struct MoveList *ml, int from, BB moves, enum Piece piece,
               enum MoveType mt) {
  while (moves) {
    int to = lsb_idx(moves);
    moves &= moves - 1;
    Move m = new_move(from, to, piece, NONE, mt);
    add_move(ml, m);
  }
}

#define ADD_MOVES(ml, piece, move_value, pieces, move_type)                    \
  while (pieces) {                                                             \
    int from = lsb_idx(pieces);                                                \
    pieces &= pieces - 1;                                                      \
    BB moves = move_value;                                                     \
    add_moves(ml, from, moves, p, move_type);                                  \
  }

void add_caps(struct MoveList *ml, struct Board *b, int from, BB moves,
              enum Piece piece, enum MoveType mt) {
  while (moves) {
    int to = lsb_idx(moves);
    moves &= moves - 1;
    Move m = new_move(from, to, piece, get_piece(b, to), mt);
    add_move(ml, m);
  }
}

#define ADD_CAPS(ml, b, piece, move_value, pieces, move_type)                  \
  while (pieces) {                                                             \
    int from = lsb_idx(pieces);                                                \
    pieces &= pieces - 1;                                                      \
    BB moves = move_value;                                                     \
    add_caps(ml, b, from, moves, p, move_type);                                \
  }

void knight_quiet(struct Board *b, struct MoveList *ml, BB pin_sqs,
                  BB target_sqs) {
  enum Piece p = KNIGHT_W + b->ctm;
  BB knights = b->pieces[p] & ~pin_sqs;
  ADD_MOVES(ml, p, KNIGHT_MOVE_TABLE[from] & ~b->util[ALL] & target_sqs,
            knights, QUIET);
}

void knight_attack(struct Board *b, struct MoveList *ml, BB pin_sqs,
                   BB target_sqs) {
  enum Piece p = KNIGHT_W + b->ctm;
  BB knights = b->pieces[p] & ~pin_sqs;
  BB opp = b->util[!b->ctm] & target_sqs;
  ADD_CAPS(ml, b, p, KNIGHT_MOVE_TABLE[from] & opp, knights, CAP)
}

void rook_quiet(struct Board *b, struct MoveList *ml, BB pin_sqs,
                BB target_sqs) {
  enum Piece p = ROOK_W + b->ctm;
  BB rooks = b->pieces[p] & ~pin_sqs;
  ADD_MOVES(ml, p, lookup_rook(b->util[ALL], from) & ~b->util[ALL] & target_sqs,
            rooks, QUIET);
}

void rook_attack(struct Board *b, struct MoveList *ml, BB pin_sqs,
                 BB target_sqs) {
  enum Piece p = ROOK_W + b->ctm;
  BB rooks = b->pieces[p] & ~pin_sqs;
  BB opp = b->util[!b->ctm] & target_sqs;
  ADD_CAPS(ml, b, p, lookup_rook(b->util[ALL], from) & opp, rooks, CAP);
}

void bishop_quiet(struct Board *b, struct MoveList *ml, BB pin_sqs,
                  BB target_sqs) {
  enum Piece p = BISHOP_W + b->ctm;
  BB bishops = b->pieces[p] & ~pin_sqs;
  ADD_MOVES(ml, p,
            lookup_bishop(b->util[ALL], from) & ~b->util[ALL] & target_sqs,
            bishops, QUIET);
}

void bishop_attack(struct Board *b, struct MoveList *ml, BB pin_sqs,
                   BB target_sqs) {
  enum Piece p = BISHOP_W + b->ctm;
  BB bishops = b->pieces[p] & ~pin_sqs;
  BB opp = b->util[!b->ctm] & target_sqs;
  ADD_CAPS(ml, b, p, lookup_bishop(b->util[ALL], from) & opp, bishops, CAP)
}

void queen_quiet(struct Board *b, struct MoveList *ml, BB pin_sqs,
                 BB target_sqs) {
  enum Piece p = QUEEN_W + b->ctm;
  BB queens = b->pieces[p] & ~pin_sqs;
  ADD_MOVES(ml, p,
            lookup_queen(b->util[ALL], from) & ~b->util[ALL] & target_sqs,
            queens, QUIET);
}

void queen_attack(struct Board *b, struct MoveList *ml, BB pin_sqs,
                  BB target_sqs) {
  enum Piece p = QUEEN_W + b->ctm;
  BB queens = b->pieces[p] & ~pin_sqs;
  BB opp = b->util[!b->ctm] & target_sqs;
  ADD_CAPS(ml, b, p, lookup_queen(b->util[ALL], from) & opp, queens, CAP)
}

void king_quiet(struct Board *b, struct MoveList *ml, BB pin_sqs,
                BB target_sqs) {
  enum Piece p = KING_W + b->ctm;
  BB king = b->pieces[p] & ~pin_sqs;
  int from = lsb_idx(king);
  add_moves(ml, from, KING_MOVE_TABLE[from] & ~b->util[ALL] & target_sqs, p,
            QUIET);
}

void king_attack(struct Board *b, struct MoveList *ml, BB pin_sqs,
                 BB target_sqs) {
  enum Piece p = KING_W + b->ctm;
  BB king = b->pieces[p] & ~pin_sqs;
  BB opp = b->util[!b->ctm] & target_sqs;
  int from = lsb_idx(king);
  add_caps(ml, b, from, KING_MOVE_TABLE[from] & opp, p, CAP);
}

void king_castle(struct Board *b, struct MoveList *ml) {
  enum Piece p = KING_W + b->ctm;
  int from = lsb_idx(b->pieces[p]);

  // if castle rights allow and no pieces are between king and rook
  BB kingside_mask = 0x60UL << (b->ctm * 56);
  if (can_kingside(b) && (b->util[ALL] & kingside_mask) == 0) {
    Move m = new_move(from, from + 2, p, 0, WKINGSIDE + b->ctm);
    add_move(ml, m);
  }

  BB queenside_mask = 0xEUL << (b->ctm * 56);
  if (can_queenside(b) && (b->util[ALL] & queenside_mask) == 0) {
    add_move(ml, new_move(from, from - 2, p, 0, WQUEENSIDE + b->ctm));
  }
}

void gen_all_moves(struct Board *b, struct MoveList *ml) {
  queen_attack(b, ml, NO_SQUARES, ALL_SQUARES);
  bishop_attack(b, ml, NO_SQUARES, ALL_SQUARES);
  rook_attack(b, ml, NO_SQUARES, ALL_SQUARES);
  knight_attack(b, ml, NO_SQUARES, ALL_SQUARES);
  king_attack(b, ml, NO_SQUARES, ALL_SQUARES);

  queen_quiet(b, ml, NO_SQUARES, ALL_SQUARES);
  bishop_quiet(b, ml, NO_SQUARES, ALL_SQUARES);
  rook_quiet(b, ml, NO_SQUARES, ALL_SQUARES);
  knight_quiet(b, ml, NO_SQUARES, ALL_SQUARES);
  king_quiet(b, ml, NO_SQUARES, ALL_SQUARES);

  if (b->ctm == WHITE) {
    wpawn_attack(b, ml, NO_SQUARES, ALL_SQUARES);
    wpawn_quiet(b, ml, NO_SQUARES, ALL_SQUARES);
    wpawn_ep(b, ml, NO_SQUARES, ALL_SQUARES);
  } else {
    bpawn_attack(b, ml, NO_SQUARES, ALL_SQUARES);
    bpawn_quiet(b, ml, NO_SQUARES, ALL_SQUARES);
    bpawn_ep(b, ml, NO_SQUARES, ALL_SQUARES);
  }

  king_castle(b, ml);
}

BB king_safe_target(struct Board *b, int king_sq) {
  BB king_moves = king_move_bb(king_sq);
  // remove the king while checking to find moving "away" from sliding pieces
  b->util[ALL] ^= b->pieces[KING_W + b->ctm];

  BB safe = 0;
  while (king_moves) {
    int to = lsb_idx(king_moves);
    king_moves &= king_moves - 1;

    if (!attackers_of_sq(b, to, !b->ctm)) {
      safe |= SQUARE(to);
    }
  }

  // restore the king
  b->util[ALL] ^= b->pieces[KING_W + b->ctm];
  return safe;
}

BB pinned_sqs(struct Board *b, int king_sq) {
  BB pinned = 0;

  enum Colour opp = !b->ctm;
  BB rook_queens = b->pieces[ROOK_W + opp] | b->pieces[QUEEN_W + opp];
  BB rq_pinners =
      lookup_rook_xray(b->util[ALL], b->util[b->ctm], king_sq) & rook_queens;

  while (rq_pinners) {
    int from = lsb_idx(rq_pinners);
    rq_pinners &= rq_pinners - 1;
    pinned |= lookup_rook(b->util[ALL], from);
  }

  BB bishop_queens = b->pieces[BISHOP_W + opp] | b->pieces[QUEEN_W + opp];
  BB bq_pinners = lookup_bishop_xray(b->util[ALL], b->util[b->ctm], king_sq) &
                  bishop_queens;

  while (bq_pinners) {
    int from = lsb_idx(bq_pinners);
    bq_pinners &= bq_pinners - 1;
    BB lookup = lookup_bishop(b->util[ALL], from);
    pinned |= lookup;
  }

  if (pinned) {
    BB potential_pins = (lookup_rook(b->util[ALL], king_sq) |
                         lookup_bishop(b->util[ALL], king_sq)) &
                        b->util[b->ctm];

    pinned &= potential_pins;
  }

  return pinned;
}

BB attacker_ray(struct Board *b, int king_sq, int att_sq) {
  if (king_sq % 8 == att_sq % 8 || king_sq / 8 == att_sq / 8) {
    return lookup_rook(b->util[ALL], king_sq) &
           lookup_rook(b->util[ALL], att_sq);
  } else {
    return lookup_bishop(b->util[ALL], king_sq) &
           lookup_bishop(b->util[ALL], att_sq);
  }
}

void gen_check_moves(struct Board *b, struct MoveList *ml) {
  int king_sq = lsb_idx(b->pieces[KING_W + b->ctm]);
  BB attackers = attackers_of_sq(b, king_sq, !b->ctm);
  BB safe_moves = king_safe_target(b, king_sq);
  king_quiet(b, ml, NO_SQUARES, safe_moves);
  king_attack(b, ml, NO_SQUARES, safe_moves);

  // if there is more than one attacker there is nothing else to do
  if (attackers & (attackers - 1)) {
    LOG("more than one attacker");
    return;
  }

  BB pinned = pinned_sqs(b, king_sq);
  queen_attack(b, ml, pinned, attackers);
  bishop_attack(b, ml, pinned, attackers);
  rook_attack(b, ml, pinned, attackers);
  knight_attack(b, ml, pinned, attackers);
  if (b->ctm == WHITE) {
    wpawn_attack(b, ml, pinned, attackers);
    wpawn_ep(b, ml, pinned, attackers);
  } else {
    bpawn_attack(b, ml, pinned, attackers);
    bpawn_ep(b, ml, pinned, attackers);
  }

  int att_sq = lsb_idx(attackers);
  // if the attacker is not a sliding piece then no other quiet moves will
  // make any difference
  enum Piece att_piece = get_piece(b, att_sq);
  if (att_piece < ROOK_W && att_piece < KING_W) {
    return;
  }

  BB att_ray = attacker_ray(b, king_sq, att_sq);
  queen_quiet(b, ml, pinned, att_ray);
  bishop_quiet(b, ml, pinned, att_ray);
  rook_quiet(b, ml, pinned, att_ray);
  knight_quiet(b, ml, pinned, att_ray);
  (b->ctm == WHITE) ? wpawn_quiet(b, ml, pinned, att_ray)
                    : bpawn_quiet(b, ml, pinned, att_ray);
}

inline void gen_moves(struct Board *b, struct MoveList *ml, bool checked) {
  if (checked) {
    gen_check_moves(b, ml);
  } else {
    gen_all_moves(b, ml);
  }
}

void gen_q_moves(struct Board *b, struct MoveList *ml) {
  queen_attack(b, ml, NO_SQUARES, ALL_SQUARES);
  bishop_attack(b, ml, NO_SQUARES, ALL_SQUARES);
  rook_attack(b, ml, NO_SQUARES, ALL_SQUARES);
  knight_attack(b, ml, NO_SQUARES, ALL_SQUARES);
  king_attack(b, ml, NO_SQUARES, ALL_SQUARES);
  (b->ctm == WHITE) ? wpawn_attack(b, ml, NO_SQUARES, ALL_SQUARES)
                    : bpawn_attack(b, ml, NO_SQUARES, ALL_SQUARES);
}

// assumes the move has already been applied to the board
bool is_legal_move(struct Board *b, Move m, bool checked) {
  if (b->halfmove > 100) {
    return false;
  }

  // checked has legal move gen and no casling is required
  if (checked) {
    return true;
  }

  // TODO check the transposition table to see if this board already exists

  // check if moved into check
  int ksq = lsb_idx(b->pieces[KING_W + !b->ctm]);
  // TODO could be optimised (see rnr)
  if (attackers_of_sq(b, ksq, b->ctm)) {
    return false;
  }

  switch (m_move_type(m)) {
  case WKINGSIDE:
    return !attackers_of_sq(b, 5, BLACK) && !attackers_of_sq(b, 6, BLACK);
  case WQUEENSIDE:
    return !attackers_of_sq(b, 3, BLACK) && !attackers_of_sq(b, 2, BLACK);
  case BKINGSIDE:
    return !attackers_of_sq(b, 61, WHITE) && !attackers_of_sq(b, 62, WHITE);
  case BQUEENSIDE:
    return !attackers_of_sq(b, 59, WHITE) && !attackers_of_sq(b, 58, WHITE);
  default:
    return true;
  }
}
