const std = @import("std");
const log = std.log;
const board = @import("board.zig");
const Board = board.Board;
const movegen = @import("movegen.zig");
const uci = @import("uci.zig");

fn perftree(b: *Board, depth: usize) usize {
    if (depth == 0) {
        return 1;
    }

    var mc: usize = 0;

    var ml = movegen.MoveList.new(b);
    const checked = b.is_in_check();
    movegen.gen_moves(&ml, b, checked);

    var next: Board = undefined;
    while (ml.next()) |m| {
        b.copy_make(&next, m);

        if (!movegen.is_legal_move(&next, m, checked)) {
            continue;
        }

        mc += perftree(&next, depth - 1);
    }

    return mc;
}

fn perftree_root(w: anytype, b: *Board, depth: usize) !void {
    var total_mc: usize = 0;

    var ml = movegen.MoveList.new(b);
    const checked = b.is_in_check();
    movegen.gen_moves(&ml, b, checked);

    var next: Board = undefined;
    while (ml.next()) |m| {
        b.copy_make(&next, m);

        if (!movegen.is_legal_move(&next, m, checked)) {
            continue;
        }

        const mc = perftree(&next, depth - 1);
        total_mc += mc;
        try m.as_uci_str(w);
        try std.fmt.format(w, " {d}\n", .{mc});
    }

    try std.fmt.format(w, "\n{d}\n", .{total_mc});
}

pub fn main() !void {
    var it = std.process.args();
    _ = it.skip();

    var arg = it.next() orelse return error.NoDepthArg;
    const depth = try std.fmt.parseInt(usize, arg, 10);

    arg = it.next() orelse return error.NoFenArg;
    var b = try board.board_from_fen(arg);

    if (it.next()) |move_str| {
        b = try uci.process_moves(b, move_str);
    }

    log.debug("perftree position is:", .{});
    b.log(log.debug);

    if (it.skip()) {
        return error.TooManyArgs;
    }

    try perftree_root(std.io.getStdOut().writer(), &b, depth);
}
