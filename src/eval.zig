const std = @import("std");

const board = @import("board.zig");
const Board = board.Board;
const Piece = board.Piece;
const movegen = @import("movegen.zig");
const Move = movegen.Move;

pub const INF: i32 = 1000000;
pub const CHECKMATE: i32 = 100000;

pub const PAWN_VALUE: i32 = 100;
const KNIGHT_VALUE: i32 = 325;
const ROOK_VALUE: i32 = 500;
const BISHOP_VALUE: i32 = 325;
pub const QUEEN_VALUE: i32 = 1000;
const KING_VALUE: i32 = 99999;

pub const PIECE_VALS: [12]i32 = .{
    PAWN_VALUE,
    PAWN_VALUE,
    KNIGHT_VALUE,
    KNIGHT_VALUE,
    ROOK_VALUE,
    ROOK_VALUE,
    BISHOP_VALUE,
    BISHOP_VALUE,
    QUEEN_VALUE,
    QUEEN_VALUE,
    KING_VALUE,
    KING_VALUE,
};

const MAT_SCORES: [12]i32 = .{
    PAWN_VALUE,
    -PAWN_VALUE,
    KNIGHT_VALUE,
    -KNIGHT_VALUE,
    ROOK_VALUE,
    -ROOK_VALUE,
    BISHOP_VALUE,
    -BISHOP_VALUE,
    QUEEN_VALUE,
    -QUEEN_VALUE,
    KING_VALUE,
    -KING_VALUE,
};

pub fn eval(b: *const Board) i32 {
    var val: i32 = 0;
    for (b.pieces, 0..) |piece_bb, i| {
        val += MAT_SCORES[i] * @popCount(piece_bb);
    }
    const mul: i32 = if (b.ctm == .WHITE) 1 else -1;
    return val * mul;
}

const PROMO_MOVE_SCORE = 5000;
const CAP_MOVE_SCORE = 10000;

fn mvvlva(piece: Piece, xpiece: Piece) i32 {
    return PIECE_VALS[@intFromEnum(xpiece)] - PIECE_VALS[@intFromEnum(piece)];
}

pub fn score_move(m: Move) i32 {
    return switch (m.mt) {
        .QUIET, .DOUBLE, .WKINGSIDE, .BKINGSIDE, .WQUEENSIDE, .BQUEENSIDE => PIECE_VALS[@intFromEnum(m.piece)],
        .PROMO => PROMO_MOVE_SCORE + PIECE_VALS[@intFromEnum(m.xpiece)],
        .NPROMOCAP => CAP_MOVE_SCORE + mvvlva(.KNIGHT, m.xpiece),
        .RPROMOCAP => CAP_MOVE_SCORE + mvvlva(.ROOK, m.xpiece),
        .BPROMOCAP => CAP_MOVE_SCORE + mvvlva(.BISHOP, m.xpiece),
        .QPROMOCAP => CAP_MOVE_SCORE + mvvlva(.QUEEN, m.xpiece),
        .CAP, .EP => CAP_MOVE_SCORE + mvvlva(m.piece, m.xpiece),
    };
}
