const std = @import("std");
const Instant = std.time.Instant;

const board = @import("board.zig");
const Board = board.Board;
const movegen = @import("movegen.zig");
const Move = movegen.Move;
const tt = @import("tt.zig");
const eval = @import("eval.zig");
const UCI = @import("uci.zig").UCI;
const Timer = @import("timer.zig").Timer;

pub const MAX_DEPTH = 200;
// const TIMEOUT_MS: u64 = 7000;
const TIMEOUT_MS: u64 = std.math.maxInt(u64);

pub const SearchResult = struct {
    score: i32,
    move: Move,
};

pub fn do_search(uci: *UCI) !SearchResult {
    return iterative_deepening(uci);
}

fn iterative_deepening(uci: *UCI) !SearchResult {
    var res: ?SearchResult = null;
    var timer = try Timer().init();

    // for (1..MAX_DEPTH) |depth| {
    for (1..4) |depth| {
        std.log.debug("trying depth {d}", .{depth});
        var searcher = Searcher.init(&timer, @intCast(depth));
        res = root_search(&searcher, &uci.board, -eval.INF, eval.INF, @intCast(depth)) catch |err| {
            switch (err) {
                error.FailLow => {
                    try uci.log_uci_error("root search failed low, trying next depth", .{});
                    continue;
                },
                error.OutOfTime => break,
                else => return err,
            }
        };

        try uci.send_info(res.?, searcher.timer, searcher.nodes, depth);
    }

    return res orelse error.NoResultFound;
}

const Searcher = struct {
    timer: *Timer(),
    start_depth: i32,
    last_move: Move,
    nodes: usize,
    qnodes: usize,

    fn init(timer: *Timer(), start_depth: i32) Searcher {
        return Searcher{
            .timer = timer,
            .start_depth = start_depth,
            .last_move = undefined,
            .nodes = 0,
            .qnodes = 0,
        };
    }

    inline fn is_out_of_time(self: *Searcher) !bool {
        // TODO check this optimisation - when to read timer
        return (0xFFF & (self.nodes + self.qnodes) == 0) and try self.timer.elapsed_ns() / std.time.ns_per_ms > TIMEOUT_MS;
    }
};

// s is a *Searcher
fn root_search(s: *Searcher, b: *const Board, alpha: i32, beta: i32, depth: i32) !SearchResult {
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

        s.last_move = m;
        const score = -try alpha_beta_search(s, &next, -beta, -a, depth - 1);
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

    tt.set_entry(b.hash, best_score.?, score_type, depth, s.start_depth - depth, best_move.?);
    return SearchResult{ .score = best_score.?, .move = best_move.? };
}

fn alpha_beta_search(s: *Searcher, b: *Board, alpha: i32, beta: i32, depth: i32) !i32 {
    s.nodes += 1;
    if (try s.is_out_of_time()) return error.OutOfTime;

    var a = alpha;

    if (depth <= 0) {
        const val = try quiesce_search(s, b, alpha, beta, 0);
        // tt.set_entry(b.hash, val, .PV, 0, start_depth, null);
        return val;
    }

    if (tt.get_score(b.hash, alpha, beta, depth, s.start_depth - depth)) |score| {
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

        s.last_move = m;
        const score = -try alpha_beta_search(s, &next, -beta, -a, depth - 1);
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
        best_score = (if (checked) -eval.CHECKMATE else eval.STALEMATE) + s.start_depth - depth;
    }

    tt.set_entry(b.hash, best_score, score_type, depth, s.start_depth - depth, best_move);
    return best_score;
}

fn quiesce_search(s: *Searcher, b: *const Board, alpha: i32, beta: i32, depth: i32) !i32 {
    s.qnodes += 1;
    if (try s.is_out_of_time()) return error.OutOfTime;

    var a = alpha;
    var val = eval.eval(b);

    if (val >= beta) return val;

    if (!b.is_in_endgame()) {
        const promo_val = if (s.last_move.mt.is_promo()) eval.QUEEN_VALUE - 200 else 0;
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
            return eval.CHECKMATE - (s.start_depth - depth);
        }

        b.copy_make(&next, next_move.move);

        s.last_move = next_move.move;
        const score = -try quiesce_search(s, &next, -beta, -a, depth - 1);

        if (score >= beta) return score;
        if (score > val) val = score;
        if (score > a) a = score;
    }

    return val;
}
