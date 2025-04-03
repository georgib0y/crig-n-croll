#include "eval.h"
#include "search.h"
#include "util.h"

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

int run(char *fen, int depth) {
  struct Board b;
  board_from_fen(&b, fen);

  int best_score;
  Move best_move;

  LOG("entering ab\n");
  root_alpha_beta(&b, depth, -INF, INF, &best_score, &best_move);

  LOG("fen: %s\nbest score = %d\n", fen, best_score);
  LOGMOVE(best_move);

  return 0;
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

  return 0;
}
