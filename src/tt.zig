const std = @import("std");
const log = std.log;
const board = @import("board.zig");
const Board = board.Board;
const Colour = board.Colour;
const Piece = board.Piece;
const CastleState = board.CastleState;
const Move = @import("movegen.zig").Move;
const zobrist = @import("consts").zobrist;
const search = @import("search.zig");
const eval = @import("eval.zig");

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

pub const TT_SIZE: usize = 1 << 20;
pub const TT_MASK: usize = TT_SIZE - 1;

pub const ScoreType = enum { PV, Alpha, Beta };

// TODO maybe store just ply instead of depth?
pub const TTEntry = struct { hash: u64, score: i32, score_type: ScoreType, depth: i32, best_move: ?Move };

var tt_data: [TT_SIZE]?TTEntry = [_]?TTEntry{null} ** TT_SIZE;

pub fn clear() void {
    @memset(&tt_data, null);
}

pub fn exists(hash: u64) bool {
    const e = tt_data[hash & TT_MASK] orelse return false;
    return e.hash == hash;
}

pub fn get_best_move(hash: u64) ?Move {
    const e = tt_data[hash & TT_MASK] orelse return null;
    if (e.hash != hash) return null;
    return e.best_move;
}

pub fn get_pv_move(hash: u64) ?Move {
    const e = tt_data[hash & TT_MASK] orelse return null;
    if (e.hash != hash) return null;
    return switch (e.score_type) {
        .PV => e.best_move,
        else => null,
    };
}

fn adjust_in(score: i32, ply: i32) i32 {
    if (score >= eval.CHECKMATE - search.MAX_DEPTH) {
        return score + ply;
    }

    if (score <= -eval.CHECKMATE + search.MAX_DEPTH) {
        return score - ply;
    }

    return score;
}

fn adjust_out(score: i32, ply: i32) i32 {
    if (score >= eval.CHECKMATE - search.MAX_DEPTH) {
        return score - ply;
    }

    if (score <= -eval.CHECKMATE + search.MAX_DEPTH) {
        return score + ply;
    }

    return score;
}

// For perft
pub fn get_entry(hash: u64, depth: i32) ?TTEntry {
    const e = tt_data[hash & TT_MASK] orelse return null;
    if (e.hash != hash or e.depth != depth) return null;

    return e;
}

pub fn get_score(hash: u64, alpha: i32, beta: i32, depth: i32, ply: i32) ?i32 {
    const e = tt_data[hash & TT_MASK] orelse return null;
    if (e.hash != hash or e.depth < depth) return null;

    // TODO returning alpha/beta or e.score in a fail?
    return switch (e.score_type) {
        .PV => adjust_out(e.score, ply),
        .Alpha => if (alpha < e.score) adjust_out(alpha, ply) else null,
        .Beta => if (beta >= e.score) adjust_out(beta, ply) else null,
    };
}

pub fn set_entry(hash: u64, score: i32, score_type: ScoreType, depth: i32, ply: i32, best_move: ?Move) void {
    const existing = tt_data[hash & TT_MASK];
    if (existing) |e| if (e.depth > depth) return;

    tt_data[hash & TT_MASK] = TTEntry{
        .hash = hash,
        .score = adjust_in(score, ply),
        .score_type = score_type,
        .depth = depth,
        .best_move = best_move,
    };
}

pub const PV = struct {
    moves: [search.MAX_DEPTH]Move,
    len: usize,

    pub fn init() PV {
        return PV{ .moves = undefined, .len = 0 };
    }

    pub fn set(self: *PV, move: Move, rest: *const PV) void {
        // return;
        std.debug.assert(rest.len + 1 < search.MAX_DEPTH);
        self.moves[0] = move;
        std.mem.copyForwards(Move, self.moves[1..], rest.moves[0..rest.len]);
        self.len = 1 + rest.len;
    }

    pub fn get_move(self: *const PV, ply: i32) ?Move {
        // return null;
        std.debug.assert(ply >= 0);
        const uply: usize = @intCast(ply);
        if (uply >= self.len) return null;
        return self.moves[uply];
    }

    pub fn write_pv(self: *const PV, w: *std.Io.Writer) !void {
        for (self.moves[0..self.len]) |pv| {
            try pv.as_uci_str(w);
            _ = try w.write(" ");
        }
    }
};
