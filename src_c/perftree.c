#include "board.h"
#include "movegen.h"
#include "util.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* #define printf(...) \ */
/*   LOG(__VA_ARGS__); \ */
/*   printf(__VA_ARGS__) */

int process_moves(struct Board *b, char *moves) {
  char *token = strtok(moves, " ");
  while (token) {
    Move m = move_from_str(b, token);
    if (m == NULL_MOVE) {
      return 1;
    }

    copy_make(b, b, m);
    token = strtok(NULL, " ");
  }

  return 0;
}

long perftree(struct Board *board, int depth) {
  if (depth == 0) {
    return 1;
  }

  long mc = 0;

  struct MoveList ml = new_move_list();
  bool checked = is_in_check(board);
  gen_moves(board, &ml, checked);

  struct Board b;
  for (int i = 0; i < ml.count; i++) {
    Move m = ml.moves[i];
    copy_make(board, &b, m);

    if (!is_legal_move(&b, m, checked)) {
      continue;
    }

    mc += perftree(&b, depth - 1);
  }

  return mc;
}

void perftree_root(struct Board *board, int depth) {
  long total_mc = 0;

  struct MoveList ml = new_move_list();
  bool checked = is_in_check(board);
  gen_moves(board, &ml, checked);

  struct Board b;
  for (int i = 0; i < ml.count; i++) {
    Move m = ml.moves[i];
    copy_make(board, &b, m);

    char move_str[10];
    uci_from_move(move_str, m);

    if (!is_legal_move(&b, m, checked)) {
      LOG("Skipping:\n");
      LOGMOVE(m);
      LOGBOARD(board);
      LOGBOARD(&b);
      continue;
    }

    long mc = perftree(&b, depth - 1);
    LOG("%s %ld\n", move_str, mc);
    printf("%s %ld\n", move_str, mc);
    total_mc += mc;
  }

  LOG("\n%ld\n", total_mc);
  printf("\n%ld\n", total_mc);
  fflush(stdout);
}

int main(int argc, char **argv) {
  init();

  if (argc < 3) {
    fprintf(stderr, "Not enough argumets, need [fen] [depth]\n");
    return 1;
  }

  for (int i = 1; i < argc; i++) {
    LOG("%d: %s\n", i, argv[i]);
  }

  int depth = atoi(argv[1]);

  if (depth < 1) {
    fprintf(stderr, "Invalid depth: %s\n", argv[1]);
    return 1;
  }

  struct Board b;
  if (board_from_fen(&b, argv[2])) {
    fprintf(stderr, "Invalid fen: %s\n", argv[2]);
    return 1;
  }

  if (argc == 4) {
    if (process_moves(&b, argv[3])) {
      fprintf(stderr, "Could not process moves: %s\n", argv[3]);
      return 1;
    }
  }

  LOGBOARD(&b);
  LOGCASTLE(b.castling);
  perftree_root(&b, depth);
  return 0;
}
