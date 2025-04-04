const std = @import("std");

const board = @import("board.zig");
const Board = board.Board;
const movegen = @import("movegen.zig");
const magic = @import("magic.zig");
const util = @import("util.zig");
const log = std.log;

pub const std_options = .{ .log_level = std.log.Level.debug };

pub fn main() !void {
    try util.init();

    const depth: usize = 3;

    const b = board.default_board();
    const mc = perft(b, depth);

    std.debug.print("depth: {d}\tmovecount: {d}\n", .{ depth, mc });
}

fn perft(b: Board, depth: usize) usize {
    if (depth == 0) {
        log.debug("here", .{});
        return 1;
    }

    const checked = b.is_in_check();
    var ml = movegen.new_move_list();
    movegen.gen_moves(&ml, b, checked);

    var mc: usize = 0;
    var next: Board = undefined;
    while (ml.next()) |m| {
        b.copy_make(&next, m);

        m.log(log.debug);
        if (!movegen.is_legal_move(next, m, checked)) {
            continue;
        }

        next.log(log.debug);
        mc += perft(b, depth - 1);
    }

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
