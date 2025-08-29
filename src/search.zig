const std = @import("std");
const board = @import("board.zig");
const Board = board.Board;
const movegen = @import("movegen.zig");
const Move = movegen.Move;
const tt = @import("tt.zig");
const PV = tt.PV;
const eval = @import("eval.zig");
const UCI = @import("uci.zig").UCI;

pub const MAX_DEPTH = 200;
const TIMEOUT_MS: u64 = 7000;

pub const SearchResult = struct {
    score: i32,
    move: Move,
};

var timer: std.time.Timer = undefined;

pub fn do_search(uci: *UCI) !SearchResult {
    timer = try std.time.Timer.start();
    return iterative_deepening(uci);
}

fn iterative_deepening(uci: *UCI) !SearchResult {
    var res: ?SearchResult = null;

    var pv = PV.init();

    for (1..MAX_DEPTH) |depth| {
        std.log.debug("trying depth {d}", .{depth});
        var searcher = Searcher.init(&pv, @intCast(depth));
        res = searcher.root_search(&uci.board, -eval.INF, eval.INF, @intCast(depth)) catch |err| {
            switch (err) {
                error.FailLow => {
                    try uci.log_uci_error("root search failed low, trying next depth", .{});
                    continue;
                },
                error.FailHigh => {
                    try uci.log_uci_error("root search failed high, trying next depth", .{});
                    continue;
                },
                error.OutOfTime => break,
                else => return err,
            }
        };

        try uci.send_info(res.?, &pv, &timer, searcher.nodes, depth);
    }

    return res orelse error.NoResultFound;
}

const Searcher = struct {
    pv: *PV,
    start_depth: i32,
    last_move: Move,
    nodes: usize,
    qnodes: usize,

    fn init(pv: *PV, start_depth: i32) Searcher {
        return Searcher{
            .pv = pv,
            .start_depth = start_depth,
            .last_move = undefined,
            .nodes = 0,
            .qnodes = 0,
        };
    }

    fn out_of_time(self: *const Searcher) bool {
        // TODO check this optimisation - when to read timer
        return 0xFFF & (self.nodes + self.qnodes) == 0 and timer.read() / std.time.ns_per_ms > TIMEOUT_MS;
    }

    inline fn ply(self: *const Searcher, depth: i32) i32 {
        return self.start_depth - depth;
    }

    inline fn checked_score(self: *const Searcher, alpha: i32, beta: i32, score_type: *tt.ScoreType, depth: i32, checked: bool) i32 {
        const score = (if (checked) -eval.CHECKMATE else eval.STALEMATE) + self.ply(depth);
        if (score > beta) {
            score_type.* = .Beta;
        } else if (score < alpha) {
            score_type.* = .Alpha;
        } else {
            score_type.* = .PV;
        }
        return score;
    }

    fn root_search(self: *Searcher, b: *const Board, init_alpha: i32, beta: i32, depth: i32) !SearchResult {
        var alpha = init_alpha;

        const checked = b.is_in_check();
        var ml = movegen.MoveList.new(b, self.pv.get_move(self.start_depth, depth));
        movegen.gen_moves(&ml, checked);

        // NOTE https://www.talkchess.com/forum/viewtopic.php?p=335799#p335799
        // hgm things fail-soft is better so we go with it
        var best_score: i32 = -eval.INF;
        var best_move: ?Move = null;
        var score_type: tt.ScoreType = .Alpha;

        var has_moved = false;
        var in_pv = true;
        var node_pv = PV.init();

        var next: Board = undefined;
        while (ml.next()) |m| {
            b.copy_make(&next, m);
            movegen.push_repetition(b.hash);
            if (!movegen.is_legal_move(&next, m, checked)) {
                movegen.pop_repetition(b.hash);
                continue;
            }

            has_moved = true;
            // const score = -try alpha_beta_search(&next, m, -beta, -a, depth - 1);

            var score = -eval.INF;
            if (in_pv) {
                score = -try self.pvs(&next, -beta, -alpha, depth - 1, &node_pv);
            } else {
                score = -try self.pvs(&next, -alpha - 1, -alpha, depth - 1, &node_pv);
                // if score would raise alpha (but not cutoff) then do a full research
                if (score > alpha and score < beta) {
                    score = -try self.pvs(&next, -beta, -alpha, depth - 1, &node_pv);
                }
            }
            movegen.pop_repetition(b.hash);

            if (score > best_score) {
                best_score = score;
                best_move = m;
            }

            if (best_score > alpha) {
                alpha = best_score;
                in_pv = false;
                self.pv.set(m, &node_pv);
                score_type = .PV;
            }

            if (best_score >= beta) {
                std.log.debug("failded high with score: {d}", .{best_score});
                score_type = .Beta;
                break;
            }
        }

        // TODO ?
        self.pv.* = node_pv;

        if (!has_moved) {
            best_score = self.checked_score(alpha, beta, &score_type, depth, checked);
        }

        if (score_type == .Alpha) return error.FailLow;
        if (score_type == .Beta) return error.FailHigh;

        tt.set_entry(b.hash, best_score, score_type, depth, self.ply(depth), best_move.?);
        return SearchResult{ .score = best_score, .move = best_move.? };
    }

    fn pvs(self: *Searcher, b: *const Board, init_alpha: i32, beta: i32, depth: i32, pv: *PV) !i32 {
        var alpha = init_alpha;
        self.nodes += 1;
        if (self.out_of_time()) return error.OutOfTime;

        // depth check comes before tt as depth == 0 is a part of qsearch
        if (depth <= 0) return try self.quiesce_search(b, alpha, beta, 0);
        // if (tt.get_score(b.hash, alpha, beta, depth, self.ply(depth))) |score| return score;

        const checked = b.is_in_check();
        var ml = movegen.MoveList.new(b, self.pv.get_move(self.start_depth, depth));
        movegen.gen_moves(&ml, checked);

        var has_moved = false;
        var in_pv = true;
        var node_pv = PV.init();

        var next: Board = undefined;

        var best_score = -eval.INF;
        var best_move: ?Move = null;
        var score_type: tt.ScoreType = .Alpha;

        defer tt.set_entry(b.hash, best_score, score_type, depth, self.ply(depth), best_move);

        // do the rest of the moves with a null window
        while (ml.next()) |m| {
            b.copy_make(&next, m);
            movegen.push_repetition(next.hash);

            if (!movegen.is_legal_move(&next, m, checked)) {
                movegen.pop_repetition(next.hash);
                continue;
            }
            has_moved = true;

            if (depth == 1) self.last_move = m;

            var score = -eval.INF;
            if (in_pv) {
                score = -try self.pvs(&next, -beta, -alpha, depth - 1, &node_pv);
            } else {
                score = -try self.pvs(&next, -alpha - 1, -alpha, depth - 1, &node_pv);
                // if score would raise alpha (but not cutoff) then do a full research
                if (score > alpha and score < beta) {
                    score = -try self.pvs(&next, -beta, -alpha, depth - 1, &node_pv);
                }
            }
            movegen.pop_repetition(next.hash);

            if (score > best_score) {
                best_score = score;
                best_move = m;
            }

            if (best_score >= beta) {
                score_type = .Beta;
                break;
            }

            if (best_score > alpha) {
                score_type = .PV;
                in_pv = false;
                pv.set(m, &node_pv);
                alpha = best_score;
            }
        }

        if (!has_moved) {
            best_score = self.checked_score(alpha, beta, &score_type, depth, checked);
        }

        return best_score;
    }

    fn quiesce_search(self: *Searcher, b: *const Board, init_alpha: i32, beta: i32, depth: i32) !i32 {
        self.qnodes += 1;
        if (self.out_of_time()) return error.OutOfTime;

        var alpha = init_alpha;
        var best_score = eval.eval(b);

        if (best_score >= beta) return best_score;

        // if (!b.is_in_endgame()) {
        //     const promo_val = if (last_move.mt.is_promo()) eval.QUEEN_VALUE - 200 else 0;
        //     const delta = eval.QUEEN_VALUE + promo_val;
        //     if (best_score < alpha - delta) return best_score;
        // }

        if (best_score > alpha) alpha = best_score;

        var ml = movegen.MoveList.new(b, null);
        movegen.gen_q_moves(&ml);

        var next: Board = undefined;
        while (ml.next_scored()) |next_move| {
            // skip if SEE is negative, if this is negative then the
            // remaining moves will probably also be bad
            if (next_move.score - eval.CAP_MOVE_SCORE <= 0) break;

            if (next_move.move.xpiece == .KING or next_move.move.xpiece == .KING_B) {
                continue;
            }

            b.copy_make(&next, next_move.move);

            self.last_move = next_move.move;
            const score = -try self.quiesce_search(&next, -beta, -alpha, depth - 1);

            if (score > best_score) best_score = score;
            if (best_score >= beta) return best_score;
            if (best_score > alpha) alpha = best_score;
        }

        return best_score;
    }
};

// TODO maybe 4?
const NULL_MOVE_REDUCTION = 3;

// fn alpha_beta_search(b: *const Board, last_move: ?Move, alpha: i32, beta: i32, depth: i32) !i32 {
//     nodes += 1;
//     if (out_of_time()) return error.OutOfTime;

//     var a = alpha;

//     if (depth <= 0) {
//         const val = try quiesce_search(b, last_move, alpha, beta, 0);
//         // tt.set_entry(b.hash, val, .PV, 0, start_depth, null);
//         return val;
//     }

//     if (tt.get_score(b.hash, alpha, beta, depth, start_depth - depth)) |score| {
//         return score;
//     }

//     const checked = b.is_in_check();
//     var ml = movegen.MoveList.new(b);
//     movegen.gen_moves(&ml, checked);

//     var has_moved = false;
//     var next: Board = undefined;

//     var best_score: i32 = -eval.INF;
//     var best_move: ?Move = null;
//     var score_type: tt.ScoreType = .Alpha;
//     while (ml.next()) |m| {
//         b.copy_make(&next, m);
//         movegen.push_repetition(next.hash);

//         if (!movegen.is_legal_move(&next, m, checked)) {
//             movegen.pop_repetition(next.hash);
//             continue;
//         }

//         has_moved = true;

//         const score = -try alpha_beta_search(&next, m, -beta, -a, depth - 1);
//         movegen.pop_repetition(next.hash);

//         if (score > best_score) {
//             best_score = score;
//             best_move = m;
//         }

//         if (score > a) {
//             a = score;
//             score_type = .PV;
//         }

//         if (score >= beta) {
//             best_score = beta;
//             score_type = .Beta;
//             break;
//         }
//     }

//     if (!has_moved) {
//         score_type = .PV;
//         best_score = (if (checked) -eval.CHECKMATE else eval.STALEMATE) + start_depth - depth;
//     }

//     tt.set_entry(b.hash, best_score, score_type, depth, start_depth - depth, best_move);
//     return best_score;
// }
