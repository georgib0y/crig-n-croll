const std = @import("std");
const board = @import("board.zig");
const UCI = @import("uci.zig").UCI;
const eval = @import("eval.zig");

pub const std_options = .{ .log_level = std.log.Level.debug };

fn new_log_file() !std.fs.File {
    const logdir = try std.fs.cwd().openDir("logs", .{});

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try std.fmt.format(fbs.writer(), "log_{d}", .{std.time.milliTimestamp()});
    return logdir.createFile(fbs.getWritten(), .{});
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const positions: [2]struct {
        fen: []const u8,
        from: usize,
        to: usize,
        piece: board.Piece,
        xpiece: board.Piece,
    } = .{
        .{
            .fen = "1k1r4/1pp4p/p7/4p3/8/P5P1/1PP4P/2K1R3 w - -",
            .from = 4,
            .to = 36,
            .piece = .ROOK,
            .xpiece = .PAWN_B,
        },
        .{
            .fen = "1k1r3q/1ppn3p/p4b2/4p3/8/P2N2P1/1PP1R1BP/2K1Q3 w - -",
            .from = 19,
            .to = 36,
            .piece = .KNIGHT,
            .xpiece = .PAWN_B,
        },
    };

    for (positions) |pos| {
        const b = try board.board_from_fen(pos.fen);
        const see_score = eval.see(&b, pos.from, pos.to, pos.piece, pos.xpiece);
        std.log.debug("fen {s} see score is {d}", .{ pos.fen, see_score });
    }

    const log_file = try new_log_file();
    var game = try UCI.init(allocator, board.default_board(), log_file);

    try game.run();
}
