#include "magic.h"
#include "util.h"
#include <stdio.h>

#define TEST_SUCCESS 0
#define TEST_FAIL 1

#define NUM_ELEMS(arr) (int)(sizeof(arr) / sizeof(arr[0]))

typedef int (*TestFunc)(void);

int test_init_magics(void) {
  init_magics();

  int res = TEST_SUCCESS;

  for (int sq = 0; sq < 64; sq++) {
    BB r_exp = rmask(sq);
    BB r_lookup = lookup_rook(0, sq);
    if (r_lookup != r_exp) {
      fprintf(stderr, "Rook squares not matched, got:\n");
      fprint_bb(stderr, r_lookup);
      fprintf(stderr, "expected:\n");
      fprint_bb(stderr, r_exp);
      res = TEST_FAIL;
    }

    BB b_exp = bmask(sq);
    BB b_lookup = lookup_bishop(0, sq);
    if (r_lookup != r_exp) {
      fprintf(stderr, "Bishop squares not matched, got:\n");
      fprint_bb(stderr, b_lookup);
      fprintf(stderr, "expected:\n");
      fprint_bb(stderr, b_exp);
      res = TEST_FAIL;
    }
  }

  return res;
}

static TestFunc test_funcs[] = {test_init_magics};

int main(void) {
  for (int i = 0; i < NUM_ELEMS(test_funcs); i++) {
    fprintf(stderr, "Running test #%d\n", i + 1);
    int res = (test_funcs[i])();
    if (res != 0) {
      return TEST_FAIL + i;
    }
  }

  fprintf(stderr, "all tests passed!\n");
  return TEST_SUCCESS;
}
