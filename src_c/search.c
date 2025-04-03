#include "search.h"
#include "board.h"
#include "eval.h"
#include "movegen.h"
#include "util.h"

#define MAX_Q_PLY 50

static bool delta_prune(struct Board *b, int alpha, int eval, Move m) {
  return eval + piece_val(m_xpiece(m)) + 200 < alpha && !m_is_promo(m) &&
         !is_endgame(b);
}

int quiesce(struct Board *board, int alpha, int beta, int q_ply) {
  if (q_ply > MAX_Q_PLY) {
    LOG("hitting max ply\n");
    return alpha;
  }

  int eval = eval_position(board);

  if (eval >= beta) {
    return beta;
  }

  if (alpha < eval) {
    alpha = eval;
  }

  struct MoveList ml = new_move_list();
  gen_q_moves(board, &ml);
  score_moves(&ml);

  struct Board b;
  Move m;
  while (next_move(&ml, &m)) {
    if (delta_prune(board, alpha, eval, m)) {
      continue;
    }

    if (m_xpiece(m) >= KING_W) {
      return INF;
    }

    copy_make(board, &b, m);

    int q_score = -quiesce(&b, -beta, -alpha, q_ply + 1);

    if (q_score >= beta) {
      return beta;
    }

    if (q_score > alpha) {
      alpha = q_score;
    }
  }

  return alpha;
}

int alpha_beta(struct Board *board, int alpha, int beta, int depth) {
  if (depth == 0) {
    return quiesce(board, alpha, beta, 0);
  }

  bool checked = is_in_check(board);
  struct MoveList ml = new_move_list();
  gen_moves(board, &ml, checked);

  score_moves(&ml);

  struct Board b;
  Move m;
  while (next_move(&ml, &m)) {
    copy_make(board, &b, m);

    if (!is_legal_move(&b, m, checked)) {
      continue;
    }

    int score = -alpha_beta(&b, -beta, -alpha, depth - 1);

    if (score >= beta) {
      return beta;
    }

    if (score > alpha) {
      alpha = score;
    }
  }

  return alpha;
}

void root_alpha_beta(struct Board *board, int depth, int alpha, int beta,
                     int *best_score, Move *best_move) {
  bool checked = is_in_check(board);
  struct MoveList ml = new_move_list();
  gen_moves(board, &ml, checked);
  score_moves(&ml);

  struct Board b;
  Move m;
  while (next_move(&ml, &m)) {
    copy_make(board, &b, m);

    if (!is_legal_move(&b, m, checked)) {
      continue;
    }

    int score = -alpha_beta(&b, -beta, -alpha, depth - 1);

    if (score >= beta) {
      *best_score = score;
      *best_move = m;
      return;
    }

    if (score > alpha) {
      alpha = score;
      *best_score = score;
      *best_move = m;
    }
  }

  return;
}
