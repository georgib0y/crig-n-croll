const std = @import("std");

const board = @import("board.zig");
const Board = board.Board;
const movegen = @import("movegen.zig");
const MoveList = movegen.MoveList;
const util = @import("util.zig");
const log = std.log;
const tt = @import("tt.zig");

pub const std_options = .{ .log_level = std.log.Level.debug };

pub fn main() !void {
    try perft_fen(null, 6, 119060324);
    try perft_fen("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq -", 5, 193690690);
    try perft_fen("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", 7, 178633661);
    try perft_fen("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", 5, 15833292);
    try perft_fen("r2q1rk1/pP1p2pp/Q4n2/bbp1p3/Np6/1B3NBn/pPPP1PPP/R3K2R b KQ - 0 1", 5, 15833292);
    try perft_fen("r2q1rk1/pP1p2pp/Q4n2/bbp1p3/Np6/1B3NBn/pPPP1PPP/R3K2R b KQ - 0 1", 5, 15833292);
    try perft_fen("rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", 5, 89941194);
    try perft_fen("r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10", 5, 164075551);
}

// fen == null for startpos
pub fn perft_fen(fen: ?[]const u8, depth: i32, expected: usize) !void {
    var b = if (fen) |f| try board.board_from_fen(f) else board.default_board();
    std.debug.print("Starting perft for {s}\n", .{fen orelse "startpos"});
    var timer = try std.time.Timer.start();
    const mc = perft_hash(&b, depth);
    const dur = timer.read();

    std.debug.print("fen {s}\ndepth: {d}\nmc: {d}\nex: {d}\ntook: {d}ms\n\n", .{ fen orelse "startpos", depth, mc, expected, dur / std.time.ns_per_ms });
    tt.clear();
}

fn perft(b: *const Board, depth: usize) usize {
    if (depth == 0) {
        return 1;
    }

    const checked = b.is_in_check();
    var ml = movegen.new_move_list(depth);
    movegen.gen_moves(&ml, b, checked);

    var mc: usize = 0;
    var next: Board = undefined;
    while (ml.next()) |m| {
        b.copy_make(&next, m);

        if (!movegen.is_legal_move(&next, m, checked)) {
            continue;
        }

        mc += perft(&next, depth - 1);
    }

    return mc;
}

fn perft_hash(b: *const Board, depth: i32) i32 {
    if (depth == 0) {
        return 1;
    }

    if (tt.get_entry(b.hash, depth)) |entry| {
        return entry.score;
    }

    const checked = b.is_in_check();
    var ml = movegen.MoveList.new();
    movegen.gen_moves(&ml, b, checked);

    var mc: i32 = 0;
    var next: Board = undefined;
    while (ml.next()) |m| {
        b.copy_make(&next, m);
        if (!movegen.is_legal_move(&next, m, checked)) {
            continue;
        }

        mc += perft_hash(&next, depth - 1);
    }

    tt.set_entry(b.hash, mc, .PV, @intCast(depth));
    return mc;
}

test "fens" {
    const good_fens = [_][]const u8{ "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1", "rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq c6 0 2", "rnbqkbnr/pp1ppppp/8/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2 ", "rnbqkbnr/pp1ppppp/8/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1", "     rnbqkbnr/pp1ppppp/8/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq -      ", "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - " };

    const bad_fens = [_][]const u8{
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR KQkq - 0 1",
        "rnbaqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1",
        "rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KaQkq c6 0 2",
        "rnbqkbnr/pp1ppppp/8/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq r5 1 2 ",
        "rnbqkbnr/pp1ppppp/8/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - -1 2 ",
    };

    for (good_fens) |fen| {
        std.debug.print("testing good fen: \"{s}\"\n", .{fen});
        const b = board.board_from_fen(fen) catch return std.testing.expect(false);
        try b.display(std.io.getStdErr().writer());
    }

    for (bad_fens) |fen| {
        std.debug.print("testing badfen: \"{s}\"\n", .{fen});
        _ = board.board_from_fen(fen) catch continue;
        return std.testing.expect(false);
    }
}
