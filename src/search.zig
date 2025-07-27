const std = @import("std");
const board = @import("board.zig");
const Board = board.Board;
const movegen = @import("movegen.zig");
const Move = movegen.Move;
const tt = @import("tt.zig");
const eval = @import("eval.zig");
const UCI = @import("uci.zig").UCI;

pub const MAX_DEPTH = 200;
const TIMEOUT_MS: u64 = 7000;

pub const SearchResult = struct {
    score: i32,
    move: Move,
};

var timer: std.time.Timer = undefined;
var nodes: usize = 0;
var qnodes: usize = 0;
var start_depth: i32 = 0;

fn is_out_of_time() bool {
    // TODO check this optimisation - when to read timer
    return 0xFFF & (nodes + qnodes) == 0 and timer.read() / std.time.ns_per_ms > TIMEOUT_MS;
}

pub fn do_search(uci: *UCI) !SearchResult {
    nodes = 0;
    timer = try std.time.Timer.start();
    return iterative_deepening(uci);
}

fn iterative_deepening(uci: *UCI) !SearchResult {
    var res: ?SearchResult = null;

    for (1..MAX_DEPTH) |depth| {
        std.log.debug("trying depth {d}", .{depth});
        start_depth = @intCast(depth);
        res = root_search(&uci.board, -eval.INF, eval.INF, @intCast(depth)) catch |err| {
            switch (err) {
                error.FailLow => {
                    try uci.log_uci_error("root search failed low, trying next depth", .{});
                    continue;
                },
                error.OutOfTime => break,
                else => return err,
            }
        };

        try uci.send_info(res.?, &timer, nodes, depth);
    }

    return res orelse error.NoResultFound;
}

fn root_search(b: *const Board, alpha: i32, beta: i32, depth: i32) !SearchResult {
    var a = alpha;

    const checked = b.is_in_check();
    var ml = movegen.MoveList.new(b);
    movegen.gen_moves(&ml, checked);

    var best_score: ?i32 = null;
    var best_move: ?Move = null;
    var score_type: tt.ScoreType = .Alpha;

    var has_moved = false;
    var next: Board = undefined;
    while (ml.next()) |m| {
        b.copy_make(&next, m);
        movegen.push_repetition(b.hash);
        if (!movegen.is_legal_move(&next, m, checked)) {
            movegen.pop_repetition(b.hash);
            continue;
        }

        has_moved = true;
        const score = -try alpha_beta_search(&next, m, -beta, -a, depth - 1);
        movegen.pop_repetition(b.hash);

        if (score > best_score orelse -eval.INF) {
            best_score = score;
            best_move = m;
        }
        if (score > a) {
            a = score;
            score_type = .PV;
        }
        if (score >= beta) {
            score_type = .Beta;

            break;
        }
    }

    if (!has_moved and checked) {
        best_score = -eval.CHECKMATE;
        score_type = .PV;
    }

    if (!has_moved and !checked) {
        best_score = eval.STALEMATE;
        score_type = .PV;
    }

    if (best_score == null) return error.FailLow;

    tt.set_entry(b.hash, best_score.?, score_type, depth, start_depth - depth, best_move.?);
    return SearchResult{ .score = best_score.?, .move = best_move.? };
}

// TODO maybe 4?
const NULL_MOVE_REDUCTION = 3;

fn alpha_beta_search(b: *Board, last_move: ?Move, alpha: i32, beta: i32, depth: i32) !i32 {
    nodes += 1;
    if (is_out_of_time()) return error.OutOfTime;

    var a = alpha;

    if (depth <= 0) {
        const val = try quiesce_search(b, last_move, alpha, beta, 0);
        // tt.set_entry(b.hash, val, .PV, 0, start_depth, null);
        return val;
    }

    if (tt.get_score(b.hash, alpha, beta, depth, start_depth - depth)) |score| {
        return score;
    }

    const checked = b.is_in_check();
    var ml = movegen.MoveList.new(b);
    movegen.gen_moves(&ml, checked);

    var has_moved = false;
    var next: Board = undefined;

    var best_score: i32 = -eval.INF;
    var best_move: ?Move = null;
    var score_type: tt.ScoreType = .Alpha;
    while (ml.next()) |m| {
        b.copy_make(&next, m);
        movegen.push_repetition(b.hash);

        if (!movegen.is_legal_move(&next, m, checked)) {
            movegen.pop_repetition(b.hash);
            continue;
        }

        has_moved = true;

        const score = -try alpha_beta_search(&next, m, -beta, -a, depth - 1);
        movegen.pop_repetition(b.hash);

        if (score > best_score) {
            best_score = score;
            best_move = m;
        }

        if (score > a) {
            a = score;
            score_type = .PV;
        }

        if (score >= beta) {
            best_score = beta;
            score_type = .Beta;
            break;
        }
    }

    if (!has_moved) {
        score_type = .PV;
        best_score = (if (checked) -eval.CHECKMATE else eval.STALEMATE) + start_depth - depth;
    }

    tt.set_entry(b.hash, best_score, score_type, depth, start_depth - depth, best_move);
    return best_score;
}

fn quiesce_search(b: *const Board, last_move: ?Move, alpha: i32, beta: i32, depth: i32) !i32 {
    qnodes += 1;
    if (is_out_of_time()) return error.OutOfTime;

    var a = alpha;
    var val = eval.eval(b);

    if (val >= beta) return val;

    if (!b.is_in_endgame()) {
        const promo_val = if (last_move) |m| (if (m.mt.is_promo()) eval.QUEEN_VALUE - 200 else 0) else 0;
        const delta = eval.QUEEN_VALUE + promo_val;
        if (val < a - delta) return a;
    }

    if (a < val) a = val;

    var ml = movegen.MoveList.new(b);
    movegen.gen_q_moves(&ml);

    var next: Board = undefined;
    while (ml.next_scored()) |next_move| {
        // skip if SEE is negative, if this is negative then the
        // remaining moves will also be bad
        if (next_move.score - eval.CAP_MOVE_SCORE < 0) break;

        if (next_move.move.xpiece == .KING or next_move.move.xpiece == .KING_B) {
            // TODO This isn't quite checkmate, as there could be
            // quiet moves that could have escaped it
            return eval.CHECKMATE - (start_depth - depth);
        }

        b.copy_make(&next, next_move.move);

        const score = -try quiesce_search(&next, next_move.move, -beta, -a, depth - 1);

        if (score >= beta) return score;
        if (score > val) val = score;
        if (score > a) a = score;
    }

    return val;
}
