#include "board.h"
#include "util.h"

int main(void) {
  init();
  struct Board b = default_board();
  print_board(&b);

  return 0;
}
