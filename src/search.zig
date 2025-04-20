const std = @import("std");
const board = @import("board.zig");
const Board = board.Board;
const movegen = @import("movegen.zig");
const Move = movegen.Move;
const tt = @import("tt.zig");
const eval = @import("eval.zig");

const START_ITER_TIMEOUT_MS: u64 = 2000;

const SearchResult = struct {
    score: i32,
    move: Move,
};

pub fn do_search(b: *const Board) !SearchResult {
    return iterative_deepening(b);
    // return root_search(b, -INF, INF, 7);
}

fn iterative_deepening(b: *const Board) !SearchResult {
    // TODO better time controls
    var depth: i32 = 1;

    var res: ?SearchResult = null;

    var timer = try std.time.Timer.start();
    while (timer.read() / std.time.ns_per_ms < START_ITER_TIMEOUT_MS) : (depth += 1) {
        res = root_search(b, -eval.INF, eval.INF, depth) catch {
            std.log.err("root search failed low, trying next depth", .{});
            continue;
        };
    }

    return res orelse error.NoResultFound;
}

fn root_search(b: *const Board, alpha: i32, beta: i32, depth: i32) !SearchResult {
    var a = alpha;

    const checked = b.is_in_check();
    var ml = movegen.MoveList.new();
    movegen.gen_moves(&ml, b, checked);

    var best_score: ?i32 = null;
    var best_move: ?Move = null;

    var has_moved = false;
    var next: Board = undefined;
    while (ml.next()) |m| {
        b.copy_make(&next, m);
        if (!movegen.is_legal_move(&next, m, checked)) {
            continue;
        }

        has_moved = true;
        const score = -alpha_beta_search(&next, -beta, -a, depth);
        if (score > best_score orelse -eval.INF) {
            best_score = score;
            best_move = m;
        }
        if (score > a) a = score;
        if (score >= beta) break;
    }

    if (!has_moved) best_score = -eval.CHECKMATE;

    if (best_score == null) return error.FailLow;

    return SearchResult{ .score = best_score.?, .move = best_move.? };
}

fn alpha_beta_search(b: *const Board, alpha: i32, beta: i32, depth: i32) i32 {
    var a = alpha;

    if (depth == 0) {
        return quiesce_search(b, alpha, beta, 0);
    }

    if (tt.get_score(b.hash, alpha, beta, depth)) |score| {
        return score;
    }

    const checked = b.is_in_check();
    var ml = movegen.MoveList.new();
    movegen.gen_moves(&ml, b, checked);

    var has_moved = false;
    var next: Board = undefined;

    var best_score: i32 = -eval.INF;
    var score_type: tt.ScoreType = .Alpha;
    while (ml.next()) |m| {
        b.copy_make(&next, m);
        if (!movegen.is_legal_move(&next, m, checked)) {
            continue;
        }

        has_moved = true;

        const score = -alpha_beta_search(&next, -beta, -a, depth - 1);
        if (score > best_score) {
            best_score = score;
            // TODO this when best_score raises or when alpha?
            score_type = .PV;
        }
        if (score > a) a = score;
        if (score >= beta) {
            best_score = beta;
            score_type = .Beta;
            break;
        }
    }

    if (!has_moved) {
        best_score = -eval.CHECKMATE + depth;
        score_type = .PV;
    }

    tt.set_entry(b.hash, best_score, score_type, depth);
    return best_score;
}

fn quiesce_search(b: *const Board, alpha: i32, beta: i32, depth: i32) i32 {
    var a = alpha;
    var val = eval.eval(b);

    // TODO depth cuttoff not ideal
    // if (depth < -6) return val;
    if (val >= beta) return val;

    // if (val < a - QUEEN_VALUE) return a;

    if (a < val) a = val;

    var ml = movegen.MoveList.new();
    movegen.gen_q_moves(&ml, b);

    var next: Board = undefined;
    while (ml.next()) |m| {
        if (m.xpiece == .KING or m.xpiece == .KING_B) {
            return eval.CHECKMATE - depth;
        }

        b.copy_make(&next, m);

        const score = -quiesce_search(&next, -beta, -a, depth - 1);

        if (score >= beta) return score;
        if (score > val) val = score;
        if (score > a) a = score;
    }

    return val;
}
