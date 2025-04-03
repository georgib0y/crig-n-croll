#include "board.h"
#include "util.h"

static char *good_fens[] = {
    "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
    "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1",
    "rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq c6 0 2",
    "rnbqkbnr/pp1ppppp/8/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2 ",
    "rnbqkbnr/pp1ppppp/8/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1",
    "     rnbqkbnr/pp1ppppp/8/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq -      ",
    "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - "};

static char *bad_fens[] = {
    "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR KQkq - 0 1",
    "rnbaqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1",
    "rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KaQkq c6 0 2",
    "rnbqkbnr/pp1ppppp/8/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq r5 1 2 ",
    "rnbqkbnr/pp1ppppp/8/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - -1 2 ",
};

static int test_good_fens(void) {
  for (int i = 0; i < 6; i++) {
    struct Board b;
    LOG("\n\nTesting good fen: %s\n\n", good_fens[i]);
    if (board_from_fen(&b, good_fens[i])) {
      LOG("board failed to parse when it should have:\n");
      LOGBOARD(&b);
      return 1;
    }
    LOGBOARD(&b);
  }

  return 0;
}

static int test_bad_fens(void) {
  for (int i = 0; i < 5; i++) {
    struct Board b;
    LOG("\n\nTesting bad fen: %s\n\n", bad_fens[i]);
    if (!board_from_fen(&b, bad_fens[i])) {
      LOG("board successfully parsed when it shouldnt have:\n");
      LOGBOARD(&b);
      return 1;
    }
  }

  return 0;
}

int main(void) {
  if (test_good_fens()) {
    LOG("testing good fens failed\n");
    return 1;
  }

  if (test_bad_fens()) {
    LOG("testing bad fens failed\n");
    return 1;
  }

  return 0;
}
