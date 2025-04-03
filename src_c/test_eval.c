#include "board.h"
#include "eval.h"
#include "movegen.h"
#include "util.h"
#include <stdint.h>

static uint64_t total_moves = 0;

struct TestPos {
  char *fen;
  int depth;
};

#define NUM_TESTS (int)(sizeof(test_poss) / sizeof(test_poss[i]))
static const struct TestPos test_poss[] = {
    {"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", 6},
    {"r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq -", 5},
    {"8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - -", 7},
    {"r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", 6},
    {"rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", 5},
    {"r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10",
     5}};

int val_perft(struct Board *board, int depth) {
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

    int32_t mg, eg;
    eval_board(&b, &mg, &eg);
    if (b.mg_val != mg || b.eg_val != eg) {
      LOG("expected values (mg, eg): %d, %d, got %d, %d \n", mg, eg, b.mg_val,
          b.eg_val);
      LOGBOARD(&b);
      LOGMOVE(m);
      return 1;
    }

    if (!is_legal_move(&b, m, checked)) {
      continue;
    }

    if (val_perft(&b, depth - 1)) {
      return 1;
    }
  }

  return 0;
}

int run(char *fen, int depth) {
  struct Board b;
  board_from_fen(&b, fen);
  return val_perft(&b, depth);
}

int main(void) {
  init();
  for (int i = 0; i < NUM_TESTS; i++) {
    struct TestPos t = test_poss[i];
    fprintf(stderr, "testing fen %s\ndepth %d\n\n", t.fen, t.depth);
    if (run(t.fen, t.depth)) {
      return 1;
    }
  }

  printf("tested %ld moves\n", total_moves);
  return 0;
}
