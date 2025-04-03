#include "board.h"
#include "movegen.h"
#include "util.h"
#include <stdlib.h>
#include <time.h>

#define MAX_DEPTH 9

static long move_count = 0;
static int mt_counts[13];

static long results[] = {0,       20,        400,        8902,       197281,
                         4865609, 119060324, 3195901860, 84998978956};

static inline void count_move(Move m) { mt_counts[m_move_type(m)]++; }

static void show_mt_counts(void) {
  for (int i = 0; i < 13; i++) {
    LOG("%s: %d\n", movetype_name(i), mt_counts[i]);
  }
}

void perft(struct Board *board, int depth) {
  if (depth == 0) {
    move_count++;
    return;
  }

  bool checked = is_in_check(board);

  struct MoveList ml = new_move_list();
  gen_moves(board, &ml, checked);

  struct Board b;
  Move m;
  /* for (int i = 0; i < ml.count; i++) { */
  /*   Move m = ml.moves[i]; */
  while (next_move(&ml, &m)) {
    copy_make(board, &b, m);

    if (!is_legal_move(&b, m, checked)) {
      continue;
    }

    count_move(m);

    perft(&b, depth - 1);
  }
}

int run(int depth) {
  move_count = 0;
  struct Board b = default_board();

  clock_t start = clock();
  perft(&b, depth);
  clock_t done = clock();

  double time_taken = ((double)(done - start)) / CLOCKS_PER_SEC * 1000;
  fprintf(stderr, "[depth %d] %.3fms\t\t%ld (%ld)\n", depth, time_taken,
          move_count, results[depth]);

  show_mt_counts();

  if (move_count != results[depth]) {
    return 1;
  }

  return 0;
}

#define DEFAULT_DEPTH 6

int main(int argc, char **argv) {
  init();
  for (int i = 0; i < 13; i++) {
    mt_counts[i] = 0;
  }

  int depth = DEFAULT_DEPTH;

  if (argc == 2) {
    depth = atoi(argv[1]);
    if (depth <= 0) {
      fprintf(stderr, "invlaid depth\n");
      return 1;
    }
  }

  for (int d = 1; d <= depth; d++) {
    if (run(d)) {
      return 1;
    }
  }

  return 0;
}
