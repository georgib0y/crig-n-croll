const std = @import("std");

const board = @import("board.zig");
const Board = board.Board;

const movegen = @import("movegen.zig");
const Move = movegen.Move;

pub const INF: i32 = 1000000;

pub const PAWN_VALUE: i32 = 100;
const KNIGHT_VALUE: i32 = 325;
const ROOK_VALUE: i32 = 500;
const BISHOP_VALUE: i32 = 325;
pub const QUEEN_VALUE: i32 = 1000;
const KING_VALUE: i32 = 99999;

const PIECE_VALS: [12]i32 = .{
    PAWN_VALUE,
    PAWN_VALUE,
    KNIGHT_VALUE,
    KNIGHT_VALUE,
    ROOK_VALUE,
    ROOK_VALUE,
    BISHOP_VALUE,
    BISHOP_VALUE,
    QUEEN_VALUE,
    QUEEN_VALUE,
    KING_VALUE,
    KING_VALUE,
};

const MAT_SCORES: [12]i32 = .{
    PAWN_VALUE,
    -PAWN_VALUE,
    KNIGHT_VALUE,
    -KNIGHT_VALUE,
    ROOK_VALUE,
    -ROOK_VALUE,
    BISHOP_VALUE,
    -BISHOP_VALUE,
    QUEEN_VALUE,
    -QUEEN_VALUE,
    KING_VALUE,
    -KING_VALUE,
};

fn eval(b: *const Board) i32 {
    var val: i32 = 0;
    for (b.pieces, 0..) |piece_bb, i| {
        val += MAT_SCORES[i] * @popCount(piece_bb);
    }
    const mul: i32 = if (b.ctm == .WHITE) 1 else -1;
    return val * mul;
}

pub fn root_search(b: *const Board, alpha: i32, beta: i32, depth: usize) !struct { i32, Move } {
    var a = alpha;

    const checked = b.is_in_check();
    var ml = movegen.new_move_list(depth);
    movegen.gen_moves(&ml, b, checked);

    var best_score: ?i32 = null;
    var best_move: ?Move = null;

    var next: Board = undefined;
    while (ml.next()) |m| {
        b.copy_make(&next, m);
        if (!movegen.is_legal_move(&next, m, checked)) {
            continue;
        }

        const score = -alpha_beta_search(&next, -beta, -a, depth - 1);
        if (score > best_score orelse -INF) {
            best_score = score;
            best_move = m;
        }
        if (score > a) a = score;
        if (score >= beta) break;
    }

    if (best_score == null) return error.FailLow;

    return .{ best_score.?, best_move.? };
}

fn alpha_beta_search(b: *const Board, alpha: i32, beta: i32, depth: usize) i32 {
    var a = alpha;

    if (depth == 0) {
        return eval(b);
    }

    const checked = b.is_in_check();
    var ml = movegen.new_move_list(depth);
    movegen.gen_moves(&ml, b, checked);

    var next: Board = undefined;

    var best_score: i32 = -INF;
    while (ml.next()) |m| {
        b.copy_make(&next, m);
        if (!movegen.is_legal_move(&next, m, checked)) {
            continue;
        }

        const score = -alpha_beta_search(&next, -beta, -a, depth - 1);
        if (score > best_score) best_score = score;
        if (score > a) a = score;
        if (score >= beta) break;
    }

    return best_score;
}
