const std = @import("std");
const board = @import("board.zig");
const Board = board.Board;
const movegen = @import("movegen.zig");
const Move = movegen.Move;
const tt = @import("tt.zig");
const eval = @import("eval.zig");
const UCI = @import("uci.zig").UCI;

pub const MAX_DEPTH = 200;
const TIMEOUT_MS: u64 = 5000;

pub const SearchResult = struct {
    score: i32,
    move: Move,
};

var timer: std.time.Timer = undefined;
var nodes: usize = 0;
var start_depth: i32 = 0;

fn is_out_of_time() bool {
    // TODO check this optimisation - when to read timer
    return 0xFFF & nodes == 0 and timer.read() / std.time.ns_per_ms > TIMEOUT_MS;
}

pub fn do_search(uci: *UCI, b: *const Board) !SearchResult {
    nodes = 0;
    timer = try std.time.Timer.start();
    return iterative_deepening(uci, b);
}

fn iterative_deepening(uci: *UCI, b: *const Board) !SearchResult {
    var res: ?SearchResult = null;

    for (1..MAX_DEPTH) |depth| {
        std.log.debug("trying depth {d}", .{depth});
        start_depth = @intCast(depth);
        res = root_search(b, -eval.INF, eval.INF, @intCast(depth)) catch |err| {
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
    movegen.gen_moves(&ml, b, checked);

    var best_score: ?i32 = null;
    var best_move: ?Move = null;
    var score_type: tt.ScoreType = .Alpha;

    var has_moved = false;
    var next: Board = undefined;
    while (ml.next()) |m| {
        b.copy_make(&next, m);
        if (!movegen.is_legal_move(&next, m, checked)) {
            continue;
        }

        has_moved = true;
        const score = -try alpha_beta_search(&next, -beta, -a, depth);
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

fn alpha_beta_search(b: *const Board, alpha: i32, beta: i32, depth: i32) !i32 {
    nodes += 1;
    if (is_out_of_time()) return error.OutOfTime;

    var a = alpha;

    if (depth == 0) {
        return quiesce_search(b, alpha, beta, 0);
    }

    if (tt.get_score(b.hash, alpha, beta, depth, start_depth - depth)) |score| {
        return score;
    }

    const checked = b.is_in_check();
    var ml = movegen.MoveList.new(b);
    movegen.gen_moves(&ml, b, checked);

    var has_moved = false;
    var next: Board = undefined;

    var best_score: i32 = -eval.INF;
    var best_move: ?Move = null;
    var score_type: tt.ScoreType = .Alpha;
    while (ml.next()) |m| {
        b.copy_make(&next, m);

        // const inc = eval.eval(&next);
        // const full = eval.board_score(&next);

        // if (inc != full) {
        //     std.log.err("full eval {d} not eq to inc eval {d}", .{ full, inc });
        //     std.log.err("full = mg: {d} eg {d} phase {d}", eval.eval_board_full(&next));
        //     std.log.err("inc = mg: {d} eg {d} phase {d}", .{ next.mg_val, next.eg_val, next.phase });

        //     m.log(std.log.err);
        //     next.log(std.log.err);
        // }

        if (!movegen.is_legal_move(&next, m, checked)) {
            continue;
        }

        has_moved = true;

        const score = -try alpha_beta_search(&next, -beta, -a, depth - 1);
        if (score > best_score) {
            best_score = score;
            best_move = m;
        }

        if (score > a) {
            a = score;
            // TODO this when best_score raises or when alpha?
            score_type = .PV;
        }

        if (score >= beta) {
            best_score = beta;
            score_type = .Beta;
            break;
        }
    }

    if (!has_moved and checked) {
        best_score = -eval.CHECKMATE + (start_depth - depth);
        score_type = .PV;
    }

    if (!has_moved and !checked) {
        best_score = eval.STALEMATE;
        score_type = .PV;
    }

    tt.set_entry(b.hash, best_score, score_type, depth, start_depth - depth, best_move);
    return best_score;
}

fn quiesce_search(b: *const Board, alpha: i32, beta: i32, depth: i32) !i32 {
    nodes += 1;
    if (is_out_of_time()) return error.OutOfTime;

    var a = alpha;
    var val = eval.eval(b);

    // TODO depth cuttoff not ideal
    // if (depth < -6) return val;
    if (val >= beta) return val;

    // if (val < a - QUEEN_VALUE) return a;

    if (a < val) a = val;

    var ml = movegen.MoveList.new(b);
    movegen.gen_q_moves(&ml, b);

    var next: Board = undefined;
    while (ml.next()) |m| {
        if (m.xpiece == .KING or m.xpiece == .KING_B) {
            // TODO This isn't quite checkmate, as there could be
            // quiet moves that could have escaped it
            return eval.CHECKMATE - (start_depth - depth);
        }

        b.copy_make(&next, m);

        const score = -try quiesce_search(&next, -beta, -a, depth - 1);

        if (score >= beta) return score;
        if (score > val) val = score;
        if (score > a) a = score;
    }

    return val;
}
