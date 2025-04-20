const std = @import("std");

const board = @import("board.zig");
const Board = board.Board;
const movegen = @import("movegen.zig");
const MoveList = movegen.MoveList;
const util = @import("util.zig");
const log = std.log;
const tt = @import("tt.zig");
const search = @import("search.zig");

pub const std_options = .{ .log_level = std.log.Level.debug };

pub fn main() !void {
    try search_fen(null);
    try search_fen("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq -");
    try search_fen("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1");
    try search_fen("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1");
    try search_fen("r2q1rk1/pP1p2pp/Q4n2/bbp1p3/Np6/1B3NBn/pPPP1PPP/R3K2R b KQ - 0 1");
    try search_fen("rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8");
    try search_fen("r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10");
}

// fen == null for startpos
pub fn search_fen(fen: ?[]const u8) !void {
    var b = if (fen) |f| try board.board_from_fen(f) else board.default_board();
    std.debug.print("Starting search for {s}\n", .{fen orelse "startpos"});

    const res = search.do_search(&b) catch {
        log.err("{s} failed low!", .{fen orelse "startpos"});
        return;
    };

    std.debug.print("fen: {s}\nscore: {d}\nmove: ", .{ fen orelse "startpos", res.score });
    res.move.log(std.debug.print);
    std.debug.print("\n", .{});

    tt.clear();
}
