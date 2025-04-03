const std = @import("std");

const board = @import("board.zig");
const BB = board.BB;
const Board = board.Board;
const Piece = board.Piece;
const movegen = @import("movegen.zig");
const Move = movegen.Move;
const MoveType = movegen.MoveType;
const magic = @import("magic.zig");

pub fn init() void {
    movegen.init_moves();
    magic.init_magics();
}

fn write_sq(w: anytype, sq: usize) !void {
    if (sq > 64) {
        try std.fmt.format(w, "out of bounds ({d})", .{sq});
    }

    const file: u8 = @as(u8, @intCast(sq % 8)) + 'a';
    const rank: u8 = @as(u8, @intCast(sq / 8)) + '1';
    try std.fmt.format(w, "{c}{c}", .{ file, rank });
}

pub fn sq_from_str(sq_str: []const u8) !usize {
    if (sq_str.len != 2) {
        return error.InvalidSqStrBadLen;
    }

    const file = sq_str[0];
    const rank = sq_str[1];

    if (file < 'a' or file > 'h' or rank < '1' or rank > '8') {
        return error.InvalidSqStrBadChar;
    }

    return @as(usize, (rank - '1') * 8 + (file - 'a'));
}

pub fn promo_from_char(promo: u8, c: board.Colour) ?Piece {
    const p = board.piece_from_char(promo) orelse return null;
    return switch (p) {
        Piece.PAWN, Piece.PAWN_B, Piece.KING, Piece.KING_B => null,
        else => @enumFromInt(@intFromEnum(p) + @intFromEnum(c)),
    };
}

pub fn display_move(m: Move, w: anytype) !void {
    try std.fmt.format(w, "from: ", .{});
    try write_sq(w, @as(usize, m.from));
    try std.fmt.format(w, " ({d})", .{m.from});

    try std.fmt.format(w, ", to: ", .{});
    try write_sq(w, @as(usize, m.to));
    try std.fmt.format(w, " ({d})", .{m.to});

    try std.fmt.format(w, ", piece: {s}, xpeice {s}, mt: {s}\n", .{
        @tagName(@as(Piece, @enumFromInt(m.piece))),
        @tagName(@as(Piece, @enumFromInt(m.xpiece))),
        @tagName(m.mt),
    });
}

pub fn move_as_uci_str(m: Move, w: anytype) !void {
    try write_sq(w, @as(usize, m.from));
    try write_sq(w, @as(usize, m.to));
    switch (m.mt) {
        MoveType.PROMO => {
            const xpiece = @as(Piece, @enumFromInt(m.xpiece));
            const c = std.ascii.toLower(board.char_from_piece(xpiece));
            try std.fmt.format(w, "{c}", .{c});
        },
        MoveType.NPROMOCAP, MoveType.RPROMOCAP, MoveType.BPROMOCAP, MoveType.QPROMOCAP => |mt| {
            const c = std.ascii.toLower(@tagName(mt)[0]);
            try std.fmt.format(w, "{c}", .{c});
        },
        else => {},
    }
}

pub fn log_bb(bb: BB, comptime log_fn: fn (comptime []const u8, anytype) void) void {
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    // 256 bytes should always be enough to print a bb
    display_bb(bb, fbs.writer()) catch unreachable;
    log_fn("\n{s}", .{fbs.getWritten()});
}

pub fn display_bb(bb: BB, writer: anytype) !void {
    var i: usize = 8;
    while (i > 0) : (i -= 1) {
        try std.fmt.format(writer, "{d} ", .{i});
        var sq = (i - 1) * 8;
        while (sq < i * 8) : (sq += 1) {
            // like get_piece but wont stop printing if there are multiple pieces on the same sq
            if (bb & board.square(sq) > 0) {
                try std.fmt.format(writer, " X ", .{});
            } else {
                try std.fmt.format(writer, " . ", .{});
            }
        }
        try std.fmt.format(writer, "\n", .{});
    }

    try std.fmt.format(writer, "\n   A  B  C  D  E  F  G  H\n\n", .{});
}

pub fn log_board(b: Board, comptime log_fn: fn (comptime []const u8, anytype) void) void {
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    // 256 bytes will always be enough to print a board
    b.display(fbs.writer()) catch unreachable;
    log_fn("\n{s}", .{fbs.getWritten()});
}

pub fn display_board(b: Board, writer: anytype) !void {
    var i: usize = 8;
    while (i > 0) : (i -= 1) {
        try std.fmt.format(writer, "{d} ", .{i});
        var sq = (i - 1) * 8;
        while (sq < i * 8) : (sq += 1) {
            try std.fmt.format(writer, " ", .{});
            // like get_piece but wont stop printing if there are multiple pieces on the same sq
            const bb = board.square(sq);
            var printed = false;
            inline for (0.., b.pieces) |p, pbb| {
                if (pbb & bb > 0) {
                    try std.fmt.format(writer, "{c}", .{board.char_from_piece(@enumFromInt(p))});
                    printed = true;
                }
            }
            if (!printed) {
                try std.fmt.format(writer, ".", .{});
            }
            try std.fmt.format(writer, " ", .{});
        }
        try std.fmt.format(writer, "\n", .{});
    }

    try std.fmt.format(writer, "\n   A  B  C  D  E  F  G  H\n\n", .{});
}
