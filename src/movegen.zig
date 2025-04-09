const std = @import("std");
const log = std.log;

const board = @import("board.zig");
const Board = board.Board;
const BB = board.BB;
const Colour = board.Colour;
const square = board.square;
const Piece = board.Piece;
const File = board.File;
const Rank = board.Rank;
const util = @import("util.zig");
const log_bb = util.log_bb;

const built_movegen = @import("built_movegen");
const pawn_attack_table = built_movegen.pawn_attack_table;
const knight_move_table = built_movegen.knight_move_table;
const king_move_table = built_movegen.king_move_table;
const super_moves = built_movegen.super_moves;
pub const rook_magics = built_movegen.rook_magics;
const rook_move_table = built_movegen.rook_move_table;
pub const bishop_magics = built_movegen.bishop_magics;
const bishop_move_table = built_movegen.bishop_move_table;

const NO_SQUARES = 0;
const ALL_SQUARES = 0xFFFFFFFFFFFFFFFF;

const PROMO_CAP_MTS = [4]MoveType{ MoveType.NPROMOCAP, MoveType.RPROMOCAP, MoveType.BPROMOCAP, MoveType.QPROMOCAP };
const PROMO_PIECES_W = [4]Piece{ Piece.KNIGHT, Piece.ROOK, Piece.BISHOP, Piece.QUEEN };
const PROMO_PIECES_B = [4]Piece{ Piece.KNIGHT_B, Piece.ROOK_B, Piece.BISHOP_B, Piece.QUEEN_B };

pub const MoveType = enum(u8) {
    QUIET,
    DOUBLE,
    CAP,
    WKINGSIDE,
    BKINGSIDE,
    WQUEENSIDE,
    BQUEENSIDE,
    PROMO,
    NPROMOCAP,
    RPROMOCAP,
    BPROMOCAP,
    QPROMOCAP,
    EP,

    pub fn is_promo(self: MoveType) bool {
        return switch (self) {
            MoveType.PROMO, MoveType.NPROMOCAP, MoveType.BPROMOCAP, MoveType.RPROMOCAP, MoveType.QPROMOCAP => true,
            else => false,
        };
    }

    pub fn is_cap(self: MoveType) bool {
        return switch (self) {
            MoveType.CAP, MoveType.NPROMOCAP, MoveType.RPROMOCAP, MoveType.BPROMOCAP, MoveType.QPROMOCAP, MoveType.EP => true,
            else => false,
        };
    }
};

pub const Move = packed struct(u32) {
    from: u8,
    to: u8,
    piece: Piece,
    xpiece: Piece,
    mt: MoveType,

    pub fn log(self: Move, comptime log_fn: fn (comptime []const u8, anytype) void) void {
        var buf: [256]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        self.display(fbs.writer()) catch unreachable;
        log_fn("{s}", .{fbs.getWritten()});
    }

    pub fn display(self: Move, w: anytype) !void {
        try util.display_move(self, w);
    }

    pub fn as_uci_str(self: Move, w: anytype) !void {
        try util.move_as_uci_str(self, w);
    }

    fn new(from: usize, to: usize, piece: Piece, xpiece: Piece, mt: MoveType) Move {
        return Move{ .from = @truncate(from), .to = @truncate(to), .piece = piece, .xpiece = xpiece, .mt = mt };
    }
};

pub fn new_move_from_uci(uci: []const u8, b: *const Board) !Move {
    if (uci.len < 4 or uci.len > 5) {
        return error.InvalidUciStrLen;
    }

    const from = try util.sq_from_str(uci[0..2]);
    const to = try util.sq_from_str(uci[2..4]);

    var promo = Piece.NONE;
    if (uci.len == 5) {
        promo = util.promo_from_char(uci[4], b.ctm) orelse Piece.NONE;
    }

    const piece = b.get_piece(from);
    if (piece == Piece.NONE) {
        return error.InvalidUciStrFromPiece;
    }

    var mt = MoveType.QUIET;

    // check for double push
    const diff = if (from < to) to - from else from - to;
    if (@intFromEnum(piece) < @intFromEnum(Piece.KNIGHT) and diff == 2) {
        mt = MoveType.DOUBLE;
    }

    if (@intFromEnum(piece) >= @intFromEnum(Piece.KING) and diff == 2) {
        if (b.ctm == Colour.WHITE) {
            mt = if (from < to) MoveType.WKINGSIDE else MoveType.WQUEENSIDE;
        } else {
            mt = if (from < to) MoveType.WKINGSIDE else MoveType.WQUEENSIDE;
        }
    }

    var xpiece = b.get_piece(to);
    if (xpiece != Piece.NONE and promo != Piece.NONE) {
        switch (promo) {
            Piece.KNIGHT, Piece.KNIGHT_B => mt = MoveType.NPROMOCAP,
            Piece.ROOK, Piece.ROOK_B => mt = MoveType.RPROMOCAP,
            Piece.BISHOP, Piece.BISHOP_B => mt = MoveType.BPROMOCAP,
            Piece.QUEEN, Piece.QUEEN_B => mt = MoveType.QPROMOCAP,
            else => {},
        }
    }

    if (xpiece == Piece.NONE and promo != Piece.NONE) {
        mt = MoveType.PROMO;
        xpiece = promo;
    }

    if (@intFromEnum(piece) < @intFromEnum(Piece.KNIGHT) and to == b.ep) {
        mt = MoveType.EP;
    }

    if (xpiece != Piece.NONE and promo == Piece.NONE) {
        mt = MoveType.CAP;
    }

    return Move.new(from, to, piece, xpiece, mt);
}

pub const MoveList = struct {
    moves: []Move,
    idx: usize,
    count: usize,

    fn append(self: *MoveList, m: Move) void {
        self.moves[self.count] = m;
        self.count += 1;
    }

    pub fn next(self: *MoveList) ?Move {
        if (self.idx == self.count) {
            return null;
        }

        const m = self.moves[self.idx];
        self.idx += 1;
        return m;
    }

    pub fn reset(self: *MoveList) void {
        self.idx = 0;
        self.count = 0;
    }

    // TODO score moves

    fn add_pawn_moves_quiet(self: *MoveList, pawns: BB, comptime piece: Piece, comptime to_offset: comptime_int, promo: Piece, comptime mt: MoveType) void {
        var p = pawns;
        while (p > 0) : (p &= p - 1) {
            const from: usize = @ctz(p);
            const to: usize = @intCast(@as(isize, @intCast(from)) + @as(isize, to_offset));
            self.append(Move.new(from, to, piece, promo, mt));
        }
    }

    fn add_pawn_moves_cap(self: *MoveList, b: *const Board, pawns: BB, comptime piece: Piece, comptime to_offset: comptime_int, comptime mt: MoveType) void {
        var p = pawns;
        while (p > 0) : (p &= p - 1) {
            const from: usize = @ctz(p);
            const to: usize = @intCast(@as(isize, @intCast(from)) + @as(isize, to_offset));
            const xpiece = b.get_piece(to);
            self.append(Move.new(from, to, piece, xpiece, mt));
        }
    }

    fn add_quiets(self: *MoveList, from: usize, quiets: BB, piece: Piece, mt: MoveType) void {
        var q = quiets;
        while (q > 0) : (q &= q - 1) {
            const to: usize = @ctz(q);
            self.append(Move.new(from, to, piece, Piece.NONE, mt));
        }
    }

    fn add_caps(self: *MoveList, b: *const Board, from: usize, caps: BB, piece: Piece, mt: MoveType) void {
        var c = caps;
        while (c > 0) : (c &= c - 1) {
            const to: usize = @ctz(c);
            self.append(Move.new(from, to, piece, b.get_piece(to), mt));
        }
    }
};

// TODO
var moves_data: [100 * 256]Move = undefined;

pub fn new_move_list(depth: usize) MoveList {
    const start = depth * 256;
    const end = start + 256;
    return MoveList{ .moves = moves_data[start..end], .idx = 0, .count = 0 };
}

fn wpawn_quiet(b: *const Board, ml: *MoveList, pin_sqs: BB, target_sqs: BB) void {
    const pawns = b.piece_bb(Piece.PAWN.with_ctm(Colour.WHITE)) & ~pin_sqs;
    const occ = b.all_bb() | ~target_sqs;
    const quiet = pawns & ~(occ >> 8);

    const push = quiet & ~@intFromEnum(Rank.R7);
    ml.add_pawn_moves_quiet(push, Piece.PAWN, 8, Piece.NONE, MoveType.QUIET);

    const double_push = (pawns & @intFromEnum(Rank.R2)) & ~(occ >> 16) & ~(b.all_bb() >> 8);
    ml.add_pawn_moves_quiet(double_push, Piece.PAWN, 16, Piece.NONE, MoveType.DOUBLE);

    const promo = quiet & @intFromEnum(Rank.R7);
    if (promo > 0) {
        for (PROMO_PIECES_W) |p| {
            ml.add_pawn_moves_quiet(promo, Piece.PAWN, 8, p, MoveType.PROMO);
        }
    }
}

fn wpawn_attack(b: *const Board, ml: *MoveList, pin_sqs: BB, target_sqs: BB) void {
    const pawns = b.piece_bb(Piece.PAWN.with_ctm(Colour.WHITE)) & ~pin_sqs;
    const opp = b.col_bb(Colour.BLACK) & target_sqs;

    const att_left = (pawns & ~@intFromEnum(File.FA)) & (opp >> 7);
    const att_right = (pawns & ~@intFromEnum(File.FH)) & (opp >> 9);

    // up left
    ml.add_pawn_moves_cap(b, att_left & ~@intFromEnum(Rank.R7), Piece.PAWN, 7, MoveType.CAP);
    // up right
    ml.add_pawn_moves_cap(b, att_right & ~@intFromEnum(Rank.R7), Piece.PAWN, 9, MoveType.CAP);

    const att_left_promo = att_left & @intFromEnum(Rank.R7);
    if (att_left_promo > 0) {
        inline for (PROMO_CAP_MTS) |mt| {
            ml.add_pawn_moves_cap(b, att_left_promo, Piece.PAWN, 7, mt);
        }
    }

    const att_right_promo = att_right & @intFromEnum(Rank.R7);
    if (att_right_promo > 0) {
        inline for (PROMO_CAP_MTS) |mt| {
            ml.add_pawn_moves_cap(b, att_right_promo, Piece.PAWN, 9, mt);
        }
    }
}

fn wpawn_ep(b: *const Board, ml: *MoveList, pin_sqs: BB, target_sqs: BB) void {
    if (b.ep >= 64) {
        return;
    }

    const pawns = b.piece_bb(Piece.PAWN.with_ctm(Colour.WHITE)) & ~pin_sqs;
    const opp = b.col_bb(Colour.BLACK) & target_sqs;

    // back right
    if ((square(b.ep) & ((pawns & ~@intFromEnum(File.FA)) << 7) & opp << 8) > 0) {
        ml.add_pawn_moves_cap(b, square(b.ep) >> 7, Piece.PAWN, 7, MoveType.EP);
    }

    if ((square(b.ep) & ((pawns & ~@intFromEnum(File.FH)) << 9) & opp << 8) > 0) {
        ml.add_pawn_moves_cap(b, square(b.ep) >> 9, Piece.PAWN, 9, MoveType.EP);
    }
}

fn bpawn_quiet(b: *const Board, ml: *MoveList, pin_sqs: BB, target_sqs: BB) void {
    const pawns = b.piece_bb(Piece.PAWN.with_ctm(Colour.BLACK)) & ~pin_sqs;
    const occ = b.all_bb() | ~target_sqs;
    const quiet = pawns & ~(occ << 8);

    const push = quiet & ~@intFromEnum(Rank.R2);
    ml.add_pawn_moves_quiet(push, Piece.PAWN_B, -8, Piece.NONE, MoveType.QUIET);

    const double_push = (pawns & @intFromEnum(Rank.R7)) & ~(occ << 16) & ~(b.all_bb() << 8);
    ml.add_pawn_moves_quiet(double_push, Piece.PAWN_B, -16, Piece.NONE, MoveType.DOUBLE);

    const promo = quiet & @intFromEnum(Rank.R2);
    if (promo > 0) {
        for (PROMO_PIECES_B) |p| {
            ml.add_pawn_moves_quiet(promo, Piece.PAWN_B, -8, p, MoveType.PROMO);
        }
    }
}

fn bpawn_attack(b: *const Board, ml: *MoveList, pin_sqs: BB, target_sqs: BB) void {
    const pawns = b.piece_bb(Piece.PAWN.with_ctm(Colour.BLACK)) & ~pin_sqs;
    const opp = b.col_bb(Colour.WHITE) & target_sqs;

    const att_left = (pawns & ~@intFromEnum(File.FA)) & (opp << 9);
    const att_right = (pawns & ~@intFromEnum(File.FH)) & (opp << 7);

    // down left
    ml.add_pawn_moves_cap(b, att_left & ~@intFromEnum(Rank.R2), Piece.PAWN_B, -9, MoveType.CAP);
    // down right
    ml.add_pawn_moves_cap(b, att_right & ~@intFromEnum(Rank.R2), Piece.PAWN_B, -7, MoveType.CAP);

    const att_left_promo = att_left & @intFromEnum(Rank.R2);
    if (att_left_promo > 0) {
        inline for (PROMO_CAP_MTS) |mt| {
            ml.add_pawn_moves_cap(b, att_left_promo, Piece.PAWN_B, -9, mt);
        }
    }

    const att_right_promo = att_right & @intFromEnum(Rank.R2);
    if (att_right_promo > 0) {
        inline for (PROMO_CAP_MTS) |mt| {
            ml.add_pawn_moves_cap(b, att_right_promo, Piece.PAWN_B, -7, mt);
        }
    }
}

fn bpawn_ep(b: *const Board, ml: *MoveList, pin_sqs: BB, target_sqs: BB) void {
    if (b.ep >= 64) {
        return;
    }

    const pawns = b.piece_bb(Piece.PAWN.with_ctm(Colour.BLACK)) & ~pin_sqs;
    const opp = b.col_bb(Colour.WHITE) & target_sqs;

    // down left
    if ((square(b.ep) & ((pawns & ~@intFromEnum(File.FA)) >> 9) & opp >> 8) > 0) {
        ml.add_pawn_moves_cap(b, square(b.ep) << 9, Piece.PAWN_B, -9, MoveType.EP);
    }

    // down right
    if ((square(b.ep) & ((pawns & ~@intFromEnum(File.FH)) >> 7) & opp >> 8) > 0) {
        ml.add_pawn_moves_cap(b, square(b.ep) << 7, Piece.PAWN_B, -7, MoveType.EP);
    }
}

fn piece_quiet(ml: *MoveList, b: *const Board, comptime piece: Piece, comptime move_fn: fn (occ: BB, from: usize) BB, pin_sqs: BB, target_sqs: BB) void {
    var pieces = b.piece_bb(piece.with_ctm(b.ctm)) & ~pin_sqs;

    while (pieces > 0) : (pieces &= pieces - 1) {
        const from: usize = @ctz(pieces);
        // const moves: BB = move_fn(b.all_bb(), from) & ~b.all_bb() & target_sqs;
        const move_bb = move_fn(b.all_bb(), from);
        const not_all = ~b.all_bb();
        const moves = move_bb & not_all & target_sqs;

        ml.add_quiets(from, moves, piece.with_ctm(b.ctm), MoveType.QUIET);
    }
}

fn piece_attack(ml: *MoveList, b: *const Board, comptime piece: Piece, comptime move_fn: fn (occ: BB, from: usize) BB, pin_sqs: BB, target_sqs: BB) void {
    var pieces = b.piece_bb(piece.with_ctm(b.ctm)) & ~pin_sqs;
    const opp = b.col_bb(b.ctm.opp()) & target_sqs;

    while (pieces > 0) : (pieces &= pieces - 1) {
        const from: usize = @ctz(pieces);
        const moves: BB = move_fn(b.all_bb(), from) & opp;
        ml.add_caps(b, from, moves, piece.with_ctm(b.ctm), MoveType.CAP);
    }
}

pub inline fn knight_move(from: usize) BB {
    return knight_move_table[from];
}

fn knight_move_wrapper(unused_occ: BB, from: usize) BB {
    _ = unused_occ;
    return knight_move(from);
}

pub inline fn king_move(from: usize) BB {
    return king_move_table[from];
}

fn king_move_wrapper(unused_occ: BB, from: usize) BB {
    _ = unused_occ;
    return king_move(from);
}

fn rook_move_wrapper(occ: BB, from: usize) BB {
    return lookup_rook(occ, from);
}

fn bishop_move_wrapper(occ: BB, from: usize) BB {
    return lookup_bishop(occ, from);
}

fn queen_move_wrapper(occ: BB, from: usize) BB {
    return lookup_queen(occ, from);
}

pub inline fn pawn_att(sq: usize, ctm: Colour) BB {
    return pawn_attack_table[sq + (64 * @as(usize, @intFromEnum(ctm)))];
}

fn king_castle(ml: *MoveList, b: *const Board) void {
    const from: usize = @ctz(b.piece_bb(Piece.KING.with_ctm(b.ctm)));

    // if castle rights allow and no pieces are between king and rook
    const shift: u6 = @intCast(@as(u6, @intFromEnum(b.ctm)) * 56);
    const kingside_mask: BB = @as(BB, 0x60) << shift;
    if (b.can_kingside() and (b.all_bb() & kingside_mask) == 0) {
        const mt = if (b.ctm == Colour.WHITE) MoveType.WKINGSIDE else MoveType.BKINGSIDE;
        ml.append(Move.new(from, from + 2, Piece.KING.with_ctm(b.ctm), Piece.NONE, mt));
    }

    const queenside_mask: BB = @as(BB, 0xE) << shift;
    if (b.can_queenside() and (b.all_bb() & queenside_mask) == 0) {
        const mt = if (b.ctm == Colour.WHITE) MoveType.WQUEENSIDE else MoveType.BQUEENSIDE;
        ml.append(Move.new(from, from - 2, Piece.KING.with_ctm(b.ctm), Piece.NONE, mt));
    }
}

fn gen_all_moves(ml: *MoveList, b: *const Board) void {
    piece_attack(ml, b, Piece.QUEEN, queen_move_wrapper, NO_SQUARES, ALL_SQUARES);
    piece_attack(ml, b, Piece.BISHOP, bishop_move_wrapper, NO_SQUARES, ALL_SQUARES);
    piece_attack(ml, b, Piece.ROOK, rook_move_wrapper, NO_SQUARES, ALL_SQUARES);
    piece_attack(ml, b, Piece.KNIGHT, knight_move_wrapper, NO_SQUARES, ALL_SQUARES);
    piece_attack(ml, b, Piece.KING, king_move_wrapper, NO_SQUARES, ALL_SQUARES);

    piece_quiet(ml, b, Piece.QUEEN, queen_move_wrapper, NO_SQUARES, ALL_SQUARES);
    piece_quiet(ml, b, Piece.BISHOP, bishop_move_wrapper, NO_SQUARES, ALL_SQUARES);
    piece_quiet(ml, b, Piece.ROOK, rook_move_wrapper, NO_SQUARES, ALL_SQUARES);
    piece_quiet(ml, b, Piece.KNIGHT, knight_move_wrapper, NO_SQUARES, ALL_SQUARES);
    piece_quiet(ml, b, Piece.KING, king_move_wrapper, NO_SQUARES, ALL_SQUARES);

    if (b.ctm == Colour.WHITE) {
        wpawn_attack(b, ml, NO_SQUARES, ALL_SQUARES);
        wpawn_quiet(b, ml, NO_SQUARES, ALL_SQUARES);
        wpawn_ep(b, ml, NO_SQUARES, ALL_SQUARES);
    } else {
        bpawn_attack(b, ml, NO_SQUARES, ALL_SQUARES);
        bpawn_quiet(b, ml, NO_SQUARES, ALL_SQUARES);
        bpawn_ep(b, ml, NO_SQUARES, ALL_SQUARES);
    }

    king_castle(ml, b);
}

fn king_safe_target(b: *const Board, king_sq: usize) BB {
    // TODO is this the best way?
    var king_moves = king_move(king_sq);
    const not_king_bb = ~square(king_sq);
    const attackers = b.ctm.opp();

    var safe: BB = 0;
    while (king_moves > 0) : (king_moves &= king_moves - 1) {
        const to: usize = @ctz(king_moves);
        var atts: BB = 0;

        atts |= pawn_att(to, attackers.opp()) & b.piece_bb(Piece.PAWN.with_ctm(attackers));
        atts |= knight_move(to) & b.piece_bb(Piece.KNIGHT.with_ctm(attackers));
        atts |= king_move(to) & b.piece_bb(Piece.KING.with_ctm(attackers));

        const rq: BB = b.piece_bb(Piece.ROOK.with_ctm(attackers)) | b.piece_bb(Piece.QUEEN.with_ctm(attackers));
        atts |= lookup_rook(b.all_bb() & not_king_bb, to) & rq;

        const bq: BB = b.piece_bb(Piece.BISHOP.with_ctm(attackers)) | b.piece_bb(Piece.QUEEN.with_ctm(attackers));
        atts |= lookup_bishop(b.all_bb() & not_king_bb, to) & bq;

        if (atts == 0) {
            safe |= square(to);
        }
    }

    return safe;
}

fn pinned_sqs(b: *const Board, king_sq: usize) BB {
    var pinned: BB = 0;

    const all_occ = b.all_bb();
    const ctm_occ = b.col_bb(b.ctm);
    const opp = b.ctm.opp();

    const rook_queens: BB = b.piece_bb(Piece.ROOK.with_ctm(opp)) | b.piece_bb(Piece.QUEEN.with_ctm(opp));
    var rq_pinners: BB =
        lookup_rook_xray(all_occ, ctm_occ, king_sq) & rook_queens;

    while (rq_pinners > 0) : (rq_pinners &= rq_pinners - 1) {
        const from: BB = @ctz(rq_pinners);
        pinned |= lookup_rook(all_occ, from);
    }

    const bishop_queens: BB = b.piece_bb(Piece.BISHOP.with_ctm(opp)) | b.piece_bb(Piece.QUEEN.with_ctm(opp));
    var bq_pinners: BB = lookup_bishop_xray(all_occ, ctm_occ, king_sq) &
        bishop_queens;

    while (bq_pinners > 0) : (bq_pinners &= bq_pinners - 1) {
        const from: BB = @ctz(bq_pinners);
        const lookup = lookup_bishop(all_occ, from);
        pinned |= lookup;
    }

    if (pinned > 0) {
        const potential_pins = (lookup_rook(all_occ, king_sq) | lookup_bishop(all_occ, king_sq)) & ctm_occ;
        pinned &= potential_pins;
    }

    return pinned;
}

fn attacker_ray(b: *const Board, king_sq: usize, att_sq: usize) BB {
    if (king_sq % 8 == att_sq % 8 or king_sq / 8 == att_sq / 8) {
        return lookup_rook(b.all_bb(), king_sq) &
            lookup_rook(b.all_bb(), att_sq);
    } else {
        return lookup_bishop(b.all_bb(), king_sq) &
            lookup_bishop(b.all_bb(), att_sq);
    }
}

fn gen_check_moves(ml: *MoveList, b: *const Board) void {
    const king_sq: usize = @ctz(b.piece_bb(Piece.KING.with_ctm(b.ctm)));

    const attackers = b.attackers_of_sq(king_sq, b.ctm.opp());
    const safe_moves = king_safe_target(b, king_sq);

    piece_quiet(ml, b, Piece.KING, king_move_wrapper, NO_SQUARES, safe_moves);
    piece_attack(ml, b, Piece.KING, king_move_wrapper, NO_SQUARES, safe_moves);

    // if there is more than one attacker there is nothing else to do
    if (attackers & (attackers - 1) > 0) {
        // log.debug("more than one attacker", .{});
        return;
    }

    const pinned = pinned_sqs(b, king_sq);

    piece_attack(ml, b, Piece.QUEEN, queen_move_wrapper, pinned, attackers);
    piece_attack(ml, b, Piece.BISHOP, bishop_move_wrapper, pinned, attackers);
    piece_attack(ml, b, Piece.ROOK, rook_move_wrapper, pinned, attackers);
    piece_attack(ml, b, Piece.KNIGHT, knight_move_wrapper, pinned, attackers);

    if (b.ctm == Colour.WHITE) {
        wpawn_attack(b, ml, pinned, attackers);
        wpawn_ep(b, ml, pinned, attackers);
    } else {
        bpawn_attack(b, ml, pinned, attackers);
        bpawn_ep(b, ml, pinned, attackers);
    }

    const att_sq: usize = @ctz(attackers);
    // if the attacker is not a sliding piece then no other quiet moves will
    // make any difference
    const att_piece = b.get_piece(att_sq);
    if (!att_piece.is_slider()) {
        return;
    }

    const att_ray = attacker_ray(b, king_sq, att_sq);

    piece_quiet(ml, b, Piece.QUEEN, queen_move_wrapper, pinned, att_ray);
    piece_quiet(ml, b, Piece.BISHOP, bishop_move_wrapper, pinned, att_ray);
    piece_quiet(ml, b, Piece.ROOK, rook_move_wrapper, pinned, att_ray);
    piece_quiet(ml, b, Piece.KNIGHT, knight_move_wrapper, pinned, att_ray);

    if (b.ctm == Colour.WHITE) wpawn_quiet(b, ml, pinned, att_ray) else bpawn_quiet(b, ml, pinned, att_ray);
}

pub fn gen_moves(ml: *MoveList, b: *const Board, checked: bool) void {
    if (checked) gen_check_moves(ml, b) else gen_all_moves(ml, b);
}

// void gen_q_moves(struct Board *b, struct MoveList *ml) {
//   queen_attack(b, ml, NO_SQUARES, ALL_SQUARES);
//   bishop_attack(b, ml, NO_SQUARES, ALL_SQUARES);
//   rook_attack(b, ml, NO_SQUARES, ALL_SQUARES);
//   knight_attack(b, ml, NO_SQUARES, ALL_SQUARES);
//   king_attack(b, ml, NO_SQUARES, ALL_SQUARES);
//   (b->ctm == WHITE) ? wpawn_attack(b, ml, NO_SQUARES, ALL_SQUARES)
//                     : bpawn_attack(b, ml, NO_SQUARES, ALL_SQUARES);
// }

fn castle_is_legal(b: *const Board, comptime sq1: usize, comptime sq2: usize, comptime attacker: Colour) bool {
    const can_sq1: bool = b.attackers_of_sq(sq1, attacker) == 0;
    const can_sq2: bool = b.attackers_of_sq(sq2, attacker) == 0;
    return can_sq1 and can_sq2;
}

// assumes the move has already been applied to the board
pub fn is_legal_move(b: *const Board, m: Move, checked: bool) bool {
    if (b.halfmove > 100) {
        return false;
    }

    // checked has legal move gen and no casling is required
    if (checked) {
        return true;
    }

    // TODO check the transposition table to see if this board already exists

    switch (m.mt) {
        MoveType.WKINGSIDE => return castle_is_legal(b, 5, 6, Colour.BLACK),
        MoveType.WQUEENSIDE => return castle_is_legal(b, 3, 2, Colour.BLACK),
        MoveType.BKINGSIDE => return castle_is_legal(b, 61, 62, Colour.WHITE),
        MoveType.BQUEENSIDE => return castle_is_legal(b, 59, 58, Colour.WHITE),
        else => {},
    }

    // check if moved into check
    const ksq: usize = @ctz(b.piece_bb(Piece.KING.with_ctm(b.ctm.opp())));

    if ((square(m.to) | square(m.from)) & super_moves[ksq] > 0 and b.attackers_of_sq(ksq, b.ctm) > 0) {
        return false;
    }

    return true;
}

const RSHIFT = 12; // !
const BSHIFT = 9;

pub inline fn lookup_bishop(occ: BB, sq: usize) BB {
    var o = occ;
    o &= bishop_magics[sq].mask;
    o = @mulWithOverflow(o, bishop_magics[sq].magic).@"0";
    o >>= 64 - BSHIFT;
    return bishop_move_table[sq][o];
}

pub fn lookup_bishop_xray(occ: BB, blockers: BB, sq: usize) BB {
    var blk = blockers;
    const atts = lookup_bishop(occ, sq);
    blk &= atts;
    return atts ^ lookup_bishop(occ ^ blk, sq);
}

pub inline fn lookup_rook(occ: BB, sq: usize) BB {
    var o = occ;
    o &= rook_magics[sq].mask;
    o = @mulWithOverflow(o, rook_magics[sq].magic).@"0";
    o >>= 64 - RSHIFT;
    return rook_move_table[sq][o];
}

pub fn lookup_rook_xray(occ: BB, blockers: BB, sq: usize) BB {
    var blk = blockers;
    const atts = lookup_rook(occ, sq);
    blk &= atts;
    return atts ^ lookup_rook(occ ^ blk, sq);
}

pub fn lookup_queen(occ: BB, sq: usize) BB {
    return lookup_bishop(occ, sq) | lookup_rook(occ, sq);
}

pub fn rook_mask(sq: usize) BB {
    return rook_magics[sq].mask;
}

pub fn bishop_mask(sq: usize) BB {
    return bishop_magics[sq].mask;
}
