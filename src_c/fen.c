#include "board.h"
#include "eval.h"
#include "hashing.h"
#include "util.h"
#include <stdlib.h>
#include <string.h>

// TODO strtok_r is POSIX only

static enum Piece piece_from_char(char p) {
  switch (p) {
  case 'P':
    return PAWN_W;
  case 'p':
    return PAWN_B;
  case 'N':
    return KNIGHT_W;
  case 'n':
    return KNIGHT_B;
  case 'R':
    return ROOK_W;
  case 'r':
    return ROOK_B;
  case 'B':
    return BISHOP_W;
  case 'b':
    return BISHOP_B;
  case 'Q':
    return QUEEN_W;
  case 'q':
    return QUEEN_B;
  case 'K':
    return KING_W;
  case 'k':
    return KING_B;
  default:
    return NONE;
  }
}

static int inc_from_char(char c) {
  if (piece_from_char(c) != NONE) {
    return 1;
  }

  if (c >= '1' && c <= '8') {
    return c - '0';
  }

  return 0;
}

static int parse_pieces(BB pieces[], BB util[], char *pieces_str) {
  // zero the piece tables
  for (int i = 0; i < 12; i++)
    pieces[i] = 0;
  for (int i = 0; i < 3; i++)
    util[i] = 0;

  // LOG("pieces are: %s\n", pieces_str);

  char *save_state;
  char *row_str = strtok_r(pieces_str, "/", &save_state);
  for (int row_start = 56; row_start >= 0; row_start -= 8) {
    if (row_str == NULL) {
      // LOG("Not enough rows, currently on sq %d\n", row_start);
      return 1;
    }

    // LOG("row str is: %s\n", row_str);

    int sq = row_start;
    for (int i = 0; i < (int)strlen(row_str); i++) {
      enum Piece p = piece_from_char(row_str[i]);
      if (p != NONE) {
        pieces[p] ^= SQUARE(sq);
      }

      if (p == NONE && (row_str[i] < '1' || row_str[i] > '8')) {
        // LOG("invalid piece: %c\n", row_str[i]);
        return 1;
      }

      sq += inc_from_char(row_str[i]);
    }

    row_str = strtok_r(NULL, "/", &save_state);
  }

  // populate util bb
  for (int i = 0; i < 12; i++) {
    if (i % 2 == 0) {
      util[WHITE] |= pieces[i];
    } else {
      util[BLACK] |= pieces[i];
    }

    util[ALL] |= pieces[i];
  }

  return 0;
}

static int parse_ctm(enum Colour *ctm, char *ctm_str) {
  // LOG("ctm is: %s\n", ctm_str);

  switch (ctm_str[0]) {
  case 'w':
    *ctm = WHITE;
    return 0;
  case 'b':
    *ctm = BLACK;
    return 0;
  default:
    // LOG("unknown ctm: %s\n", ctm_str);
    return 1;
  }
}

static int parse_castling(CastleState *cs, char *castling_str) {
  // LOG("castling is: %s\n", castling_str);
  *cs = 0;
  if (castling_str[0] == '-') {
    return 0;
  }

  for (int i = 0; i < (int)strlen(castling_str); i++) {
    switch (castling_str[i]) {
    case 'K':
      *cs |= 0x8;
      break;
    case 'Q':
      *cs |= 0x4;
      break;
    case 'k':
      *cs |= 0x2;
      break;
    case 'q':
      *cs |= 0x1;
      break;
    default:
      LOG("unknown castle char: %c\n", castling_str[i]);
      return 1;
    }
  }

  return 0;
}

static int parse_ep(char *ep, char *ep_str) {
  // LOG("ep is: %s\n", ep_str);
  if (ep_str[0] == '-') {
    *ep = 64;
    return 0;
  }

  return sq_from_str(ep, ep_str);
}

static int parse_halfmove(char *halfmove, char *hm_str) {
  *halfmove = atoi(hm_str);
  // LOG("halfmove: %d\n", *halfmove);
  return *halfmove < 0;
}

static const char *startpos_fen =
    "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";

int board_from_fen(struct Board *b, const char *fen) {
  char internal_fen[256];
  strncpy(internal_fen, fen, strlen(fen) + 1);

  LOG("fen is: %s\n", fen);

  if (strncmp(fen, "startpos", 8) == 0) {
    strncpy(internal_fen, startpos_fen, strlen(startpos_fen) + 1);
  }

  LOG("internal fen is: %s\n", internal_fen);

  char *save_state;
  char *token = strtok_r(internal_fen, " ", &save_state);

  if (token == NULL || parse_pieces(b->pieces, b->util, token)) {
    LOG("could not parse pieces, token is: %s\n", token);
    return 1;
  }

  token = strtok_r(NULL, " ", &save_state);
  if (token == NULL || parse_ctm(&b->ctm, token)) {
    LOG("could not parse ctm, token is: %s\n", token);
    return 1;
  }

  token = strtok_r(NULL, " ", &save_state);
  if (token == NULL || parse_castling(&b->castling, token)) {
    LOG("could not parse castling, token is: %s\n", token);
    return 1;
  }

  token = strtok_r(NULL, " ", &save_state);
  if (token == NULL || parse_ep(&b->ep, token)) {
    LOG("could not parse ep, token is: %s\n", token);
    return 1;
  }

#ifdef HASHING
  b->hash = hash_board(b);
  LOG("fen hash %ld\n", b->hash);
#endif

#ifdef EVAL
  int mg, eg;
  eval_board(b, &mg, &eg);
  b->mg_val = mg;
  b->eg_val = eg;
  LOG("fen vals = %d %d\n", b->mg_val, b->eg_val);
#endif

  token = strtok_r(NULL, " ", &save_state);
  // optional
  if (token == NULL) {
    LOG("no halfmove for fen\n");
    LOGBOARD(b);
    return 0;
  }
  if (parse_halfmove(&b->halfmove, token)) {
    LOG("could not parse halfmove, token is: %s\n", token);
    return 1;
  }

  LOGBOARD(b);
  return 0;
}
