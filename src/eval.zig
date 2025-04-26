const std = @import("std");

const board = @import("board.zig");
const Board = board.Board;
const Piece = board.Piece;
const movegen = @import("movegen.zig");
const Move = movegen.Move;
const consts = @import("consts");

pub const INF: i32 = 1000000;
pub const CHECKMATE: i32 = 100000;
pub const STALEMATE: i32 = 0;

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

pub const MAT_SCORES: [12]i32 = .{
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

pub const MID_PST: [12][64]i16 = .{
    consts.WPAWN_MID_PST,
    consts.BPAWN_MID_PST,
    consts.WKNIGHT_MID_PST,
    consts.BKNIGHT_MID_PST,
    consts.WBISHOP_MID_PST,
    consts.BBISHOP_MID_PST,
    consts.WROOK_MID_PST,
    consts.BROOK_MID_PST,
    consts.WQUEEN_MID_PST,
    consts.BQUEEN_MID_PST,
    consts.WKING_MID_PST,
    consts.BKING_MID_PST,
};

pub const END_PST: [12][64]i16 = .{
    consts.WPAWN_END_PST,
    consts.BPAWN_END_PST,
    consts.WKNIGHT_END_PST,
    consts.BKNIGHT_END_PST,
    consts.WBISHOP_END_PST,
    consts.BBISHOP_END_PST,
    consts.WROOK_END_PST,
    consts.BROOK_END_PST,
    consts.WQUEEN_END_PST,
    consts.BQUEEN_END_PST,
    consts.WKING_END_PST,
    consts.BKING_END_PST,
};

// _strongly_ inspired by PeSTO's eval func
// https://www.chessprogramming.org/PeSTO%27s_Evaluation_Function

// the value that a piece has to influence mid game / end game phase
pub const PIECE_PHASE_VAL: [12]u8 = .{ 0, 0, 1, 1, 1, 1, 2, 2, 4, 4, 0, 0 };

fn tapered_eval(mg: i32, eg: i32, phase: u8) i32 {
    const mg_phase = @min(phase, 24);
    const eg_phase = 24 - mg_phase;
    return @divTrunc(mg * mg_phase + eg * eg_phase, 24);
}

pub fn eval(b: *const Board) i32 {
    const mul: i32 = if (b.ctm == .WHITE) 1 else -1;
    return tapered_eval(b.mg_val, b.eg_val, b.phase) * mul;
}

pub fn eval_board_full(b: *const Board) struct { i32, i32, u8 } {
    var mg_val: i32 = 0;
    var eg_val: i32 = 0;
    var phase: u8 = 0;
    for (0..64) |sq| {
        const p = b.get_piece(sq);
        if (p == .NONE) continue;
        mg_val += MAT_SCORES[@intFromEnum(p)];
        mg_val += MID_PST[@intFromEnum(p)][sq];
        eg_val += MAT_SCORES[@intFromEnum(p)];
        eg_val += END_PST[@intFromEnum(p)][sq];
        phase += PIECE_PHASE_VAL[@intFromEnum(p)];
    }

    return .{ mg_val, eg_val, phase };
}

pub fn board_score(b: *const Board) i32 {
    const mul: i32 = if (b.ctm == .WHITE) 1 else -1;
    const mg_val, const eg_val, const phase = eval_board_full(b);
    return tapered_eval(mg_val, eg_val, phase) * mul;
}

const PROMO_MOVE_SCORE = 5000;
const CAP_MOVE_SCORE = 10000;
const TT_BEST_SCORE = 1000000;

fn mvvlva(piece: Piece, xpiece: Piece) i32 {
    return PIECE_VALS[@intFromEnum(xpiece)] - PIECE_VALS[@intFromEnum(piece)];
}

pub fn score_move(m: Move, tt_bestmove: ?Move) i32 {
    if (tt_bestmove) |bm| if (movegen.moves_eql(m, bm)) return TT_BEST_SCORE;

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
