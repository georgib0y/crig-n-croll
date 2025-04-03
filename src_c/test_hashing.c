#include "board.h"
#include "hashing.h"
#include "movegen.h"
#include "util.h"
#include <stdint.h>

static uint64_t total_moves = 0;

struct TestPos {
  char *fen;
  int depth;
};

static const struct TestPos test_poss[] = {
    {"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", 6},
    {"r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq -", 5},
    {"8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - -", 7},
    {"r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", 6},
    {"rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", 5},
    {"r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10", 5}};


int hash_perft(struct Board *board, int depth) {
  if (depth == 0) {
    total_moves++;
    return 0;
  }

  bool checked = is_in_check(board);

  struct MoveList ml = new_move_list();
  gen_moves(board, &ml, checked);

  struct Board b;
  for (int i = 0; i < ml.count; i++) {
    Move m = ml.moves[i];
    copy_make(board, &b, m);

    uint64_t hash = hash_board(&b);
    if (hash != b.hash) {
      LOG("expected hash %ld, got %ld\n", hash, b.hash);
      LOGBOARD(&b);
      LOGMOVE(m);
      LOG("ep %d\n", b.ep);
      return 1;
    }

    if (!is_legal_move(&b, m, checked)) {
      continue;
    }

    if (hash_perft(&b, depth - 1)) {
      return 1;
    }
  }

  return 0;
}

int run(char *fen, int depth) {
  struct Board b;
  board_from_fen(&b, fen);
  uint64_t hash = hash_board(&b);
  if (b.hash != hash) {
    LOG("hashes somehow not the same (exp %ld got %ld)!\n", hash, b.hash);
    return 1;
  }
  return hash_perft(&b, depth);
}

int main(void) {
  init();
  for (int i = 0; i < (int)(sizeof(test_poss) / sizeof(test_poss[i])); i++) {
    struct TestPos t = test_poss[i];
    fprintf(stderr, "testing %s\n", t.fen);
    if (run(t.fen, t.depth)) {
      fprintf(stderr, "%s failed\n", t.fen);
      return 1;
    }
  }

  printf("tested %ld moves\n", total_moves);
  return 0;
}
