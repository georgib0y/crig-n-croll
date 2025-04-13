const std = @import("std");
const log = std.log;

const board = @import("board.zig");
const Board = board.Board;
const Colour = board.Colour;
const Piece = board.Piece;
const CastleState = board.CastleState;

const Move = @import("movegen.zig").Move;

const zobrist = @import("built_movegen").zobrist;

pub fn piece_zobrist(p: Piece, sq: usize) u64 {
    return zobrist[@as(usize, @intFromEnum(p)) * 64 + sq];
}

pub fn colour_zobrist() u64 {
    return comptime zobrist[768];
}

pub const CastleStateIdx = enum(usize) {
    WKS = 3,
    WQS = 2,
    BKS = 1,
    BQS = 0,
};

pub fn castle_zobrist(comptime c: CastleStateIdx) u64 {
    return zobrist[769 + @intFromEnum(c)];
}

pub fn ep_zobrist(sq: usize) u64 {
    return zobrist[773 + (sq % 8)];
}

pub fn hash_board(b: *const Board) u64 {
    var hash: u64 = 0;

    for (b.pieces, Piece.pieces()) |piece_bb, piece| {
        for (0..64) |sq| {
            const bb = board.square(sq);
            if (piece_bb & bb > 0) {
                hash ^= piece_zobrist(piece, sq);
            }
        }
    }

    if (b.ctm == Colour.BLACK) hash ^= colour_zobrist();

    inline for ([_]CastleState{ 0b1, 0b10, 0b100, 0b1000 }, 0..) |cs, i| {
        if (b.castling & cs > 0) hash ^= castle_zobrist(@enumFromInt(i));
    }

    if (b.ep < 64) hash ^= ep_zobrist(b.ep);

    return hash;
}

pub const TT_SIZE = 1 << 20;
pub const TT_MASK = TT_SIZE - 1;

pub const TTEntry = struct { hash: u64, score: usize, depth: usize };

var tt_data: [TT_SIZE]?TTEntry = [_]?TTEntry{null} ** TT_SIZE;

pub fn clear() void {
    for (0..TT_SIZE) |i| {
        tt_data[i] = null;
    }
}

pub fn exists(hash: u64) bool {
    const e = tt_data[hash & TT_MASK] orelse return false;
    return e.hash == hash;
}

pub fn get_entry(hash: u64, depth: usize) ?TTEntry {
    const e = tt_data[hash & TT_MASK] orelse return null;
    if (e.hash != hash or e.depth != depth) return null;
    return e;
}

pub fn set_entry(hash: u64, score: usize, depth: usize) void {
    tt_data[hash & TT_MASK] = TTEntry{ .hash = hash, .score = score, .depth = depth };
}
