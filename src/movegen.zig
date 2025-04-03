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
const magic = @import("magic.zig");
const util = @import("util.zig");
const log_bb = util.log_bb;

const NO_SQUARES = 0;
const ALL_SQUARES = 0xFFFFFFFFFFFFFFFF;

const PROMO_CAP_MTS = [4]MoveType{ MoveType.NPROMOCAP, MoveType.RPROMOCAP, MoveType.BPROMOCAP, MoveType.QPROMOCAP };
const PROMO_PIECES_W = [4]Piece{ Piece.KNIGHT, Piece.ROOK, Piece.BISHOP, Piece.QUEEN };
const PROMO_PIECES_B = [4]Piece{ Piece.KNIGHT_B, Piece.ROOK_B, Piece.BISHOP_B, Piece.QUEEN_B };

var knight_move_table: [64]BB = undefined;

// TODO could move this into the build scriptx
fn init_knight_move_table() void {
    for (0..64) |i| {
        var bb: BB = 0;
        bb |= (square(i) & ~@intFromEnum(File.FA) & ~@intFromEnum(File.FB)) << 6;
        bb |= (square(i) & ~@intFromEnum(File.FA)) << 15;
        bb |= (square(i) & ~@intFromEnum(File.FH)) << 17;
        bb |= (square(i) & ~@intFromEnum(File.FG) & ~@intFromEnum(File.FH)) << 10;
        bb |= (square(i) & ~@intFromEnum(File.FH) & ~@intFromEnum(File.FG)) >> 6;
        bb |= (square(i) & ~@intFromEnum(File.FH)) >> 15;
        bb |= (square(i) & ~@intFromEnum(File.FA)) >> 17;
        bb |= (square(i) & ~@intFromEnum(File.FA) & ~@intFromEnum(File.FB)) >> 10;

        knight_move_table[i] = bb;
    }
}

var king_move_table: [64]BB = undefined;

fn init_king_move_table() void {
    for (0..64) |i| {
        var bb: BB = 0;
        const k_clear_a = square(i) & ~@intFromEnum(File.FA);
        const k_clear_h = square(i) & ~@intFromEnum(File.FH);

        bb |= square(i) << 8;
        bb |= k_clear_a << 7;
        bb |= k_clear_a >> 1;
        bb |= k_clear_a >> 9;
        bb |= k_clear_h << 9;
        bb |= k_clear_h << 1;
        bb |= k_clear_h >> 7;

        king_move_table[i] = bb;
    }
}

var pawn_attack_table: [128]BB = undefined;

fn init_pawn_attacks() void {
    for (0..64) |i| {
        const sq = square(i);

        // white
        if (sq & ~@intFromEnum(Rank.R8) > 0) {
            pawn_attack_table[i] = (sq & ~@intFromEnum(File.FA)) << 7 | (sq & ~@intFromEnum(File.FH)) << 9;
        }

        // black
        if (sq & ~@intFromEnum(Rank.R1) > 0) {
            pawn_attack_table[i + 64] = (sq & ~@intFromEnum(File.FH)) >> 7 | (sq & ~@intFromEnum(File.FA)) >> 9;
        }
    }
}

pub fn init_moves() void {
    init_pawn_attacks();
    init_knight_move_table();
    init_king_move_table();
}

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

    fn is_promo(self: MoveType) bool {
        return switch (self) {
            MoveType.PROMO, MoveType.NPROMOCAP, MoveType.BPROMOCAP, MoveType.RPROMOCAP, MoveType.QPROMOCAP => true,
            else => false,
        };
    }

    fn is_cap(self: MoveType) bool {
        return switch (self) {
            MoveType.CAP, MoveType.NPROMOCAP, MoveType.RPROMOCAP, MoveType.BPROMOCAP, MoveType.QPROMOCAP, MoveType.EP => true,
            else => false,
        };
    }
};

pub const Move = packed struct {
    from: u6,
    to: u6,
    piece: u6,
    xpiece: u6,
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
};

fn new_move(from: usize, to: usize, piece: Piece, xpiece: Piece, mt: MoveType) Move {
    return Move{ .from = @truncate(from), .to = @truncate(to), .piece = @truncate(@intFromEnum(piece)), .xpiece = @truncate(@intFromEnum(xpiece)), .mt = mt };
}

pub fn new_move_from_uci(uci: []const u8, b: Board) !Move {
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

    return new_move(from, to, piece, xpiece, mt);
}

pub const MoveList = struct {
    moves: [256]Move,
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

    // TODO score moves

    fn add_pawn_moves_quiet(self: *MoveList, pawns: BB, piece: Piece, to_offset: comptime_int, promo: Piece, mt: MoveType) void {
        var p = pawns;
        while (p > 0) : (p &= p - 1) {
            const from: usize = @ctz(p);
            const to: usize = @intCast(@as(isize, @intCast(from)) + @as(isize, to_offset));
            self.append(new_move(from, to, piece, promo, mt));
        }
    }

    fn add_pawn_moves_cap(self: *MoveList, b: Board, pawns: BB, piece: Piece, to_offset: comptime_int, mt: MoveType) void {
        var p = pawns;
        while (p > 0) : (p &= p - 1) {
            const from: usize = @ctz(p);
            const to: usize = @intCast(@as(isize, @intCast(from)) + @as(isize, to_offset));
            const xpiece = b.get_piece(to);
            self.append(new_move(from, to, piece, xpiece, mt));
        }
    }

    fn add_quiets(self: *MoveList, from: usize, quiets: BB, piece: Piece, mt: MoveType) void {
        var q = quiets;
        while (q > 0) : (q &= q - 1) {
            const to: usize = @ctz(q);
            // log.debug("add q: from {d} to {d} p {s}", .{ from, to, @tagName(piece) });
            self.append(new_move(from, to, piece, Piece.NONE, mt));
        }
    }

    fn add_caps(self: *MoveList, b: Board, from: usize, caps: BB, piece: Piece, mt: MoveType) void {
        var c = caps;
        while (c > 0) : (c &= c - 1) {
            const to: usize = @ctz(c);
            self.append(new_move(from, to, piece, b.get_piece(to), mt));
        }
    }
};

pub fn new_move_list() MoveList {
    return MoveList{ .moves = undefined, .idx = 0, .count = 0 };
}

fn wpawn_quiet(b: Board, ml: *MoveList, pin_sqs: BB, target_sqs: BB) void {
    const pawns = b.piece_bb(Piece.PAWN, Colour.WHITE) & ~pin_sqs;
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

fn wpawn_attack(b: Board, ml: *MoveList, pin_sqs: BB, target_sqs: BB) void {
    const pawns = b.piece_bb(Piece.PAWN, Colour.WHITE) & ~pin_sqs;
    const opp = b.col_bb(Colour.BLACK) & target_sqs;

    const att_left = (pawns & ~@intFromEnum(File.FA)) & (opp >> 7);
    const att_right = (pawns & ~@intFromEnum(File.FH)) & (opp >> 9);

    // up left
    ml.add_pawn_moves_cap(b, att_left & ~@intFromEnum(Rank.R7), Piece.PAWN, 7, MoveType.CAP);
    // up right
    ml.add_pawn_moves_cap(b, att_right & ~@intFromEnum(Rank.R7), Piece.PAWN, 9, MoveType.CAP);

    const att_left_promo = att_left & @intFromEnum(Rank.R7);
    if (att_left_promo > 0) {
        for (PROMO_CAP_MTS) |mt| {
            ml.add_pawn_moves_cap(b, att_left_promo, Piece.PAWN, 7, mt);
        }
    }

    const att_right_promo = att_right & @intFromEnum(Rank.R7);
    if (att_right_promo > 0) {
        for (PROMO_CAP_MTS) |mt| {
            ml.add_pawn_moves_cap(b, att_right_promo, Piece.PAWN, 9, mt);
        }
    }
}

fn wpawn_ep(b: Board, ml: *MoveList, pin_sqs: BB, target_sqs: BB) void {
    if (b.ep >= 64) {
        return;
    }

    const pawns = b.piece_bb(Piece.PAWN, Colour.WHITE) & ~pin_sqs;
    const opp = b.col_bb(Colour.BLACK) & target_sqs;

    // back right
    if ((square(b.ep) & ((pawns & ~@intFromEnum(File.FA)) << 7) & opp << 8) > 0) {
        ml.add_pawn_moves_cap(b, square(b.ep) >> 7, Piece.PAWN, 7, MoveType.EP);
    }

    if ((square(b.ep) & ((pawns & ~@intFromEnum(File.FH)) << 9) & opp << 8) > 0) {
        ml.add_pawn_moves_cap(b, square(b.ep) >> 9, Piece.PAWN, 9, MoveType.EP);
    }
}

fn bpawn_quiet(b: Board, ml: *MoveList, pin_sqs: BB, target_sqs: BB) void {
    const pawns = b.piece_bb(Piece.PAWN, Colour.BLACK) & ~pin_sqs;
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

fn bpawn_attack(b: Board, ml: *MoveList, pin_sqs: BB, target_sqs: BB) void {
    const pawns = b.piece_bb(Piece.PAWN, Colour.BLACK) & ~pin_sqs;
    const opp = b.col_bb(Colour.WHITE) & target_sqs;

    const att_left = (pawns & ~@intFromEnum(File.FA)) & (opp << 9);
    const att_right = (pawns & ~@intFromEnum(File.FH)) & (opp << 7);

    // down left
    ml.add_pawn_moves_cap(b, att_left & ~@intFromEnum(Rank.R2), Piece.PAWN_B, -9, MoveType.CAP);
    // up right
    ml.add_pawn_moves_cap(b, att_right & ~@intFromEnum(Rank.R2), Piece.PAWN_B, -7, MoveType.CAP);

    const att_left_promo = att_left & @intFromEnum(Rank.R2);
    if (att_left_promo > 0) {
        for (PROMO_CAP_MTS) |mt| {
            ml.add_pawn_moves_cap(b, att_left_promo, Piece.PAWN_B, -9, mt);
        }
    }

    const att_right_promo = att_right & @intFromEnum(Rank.R2);
    if (att_right_promo > 0) {
        for (PROMO_CAP_MTS) |mt| {
            ml.add_pawn_moves_cap(b, att_right_promo, Piece.PAWN_B, -7, mt);
        }
    }
}

fn bpawn_ep(b: Board, ml: *MoveList, pin_sqs: BB, target_sqs: BB) void {
    if (b.ep >= 64) {
        return;
    }

    const pawns = b.piece_bb(Piece.PAWN, Colour.BLACK) & ~pin_sqs;
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

fn piece_quiet(ml: *MoveList, b: Board, comptime piece: Piece, comptime move_fn: fn (occ: BB, from: usize) BB, pin_sqs: BB, target_sqs: BB) void {
    var pieces = b.piece_bb(piece, b.ctm) & ~pin_sqs;

    while (pieces > 0) : (pieces &= pieces - 1) {
        const from: usize = @ctz(pieces);
        // const moves: BB = move_fn(b.all_bb(), from) & ~b.all_bb() & target_sqs;
        const move_bb = move_fn(b.all_bb(), from);
        const not_all = ~b.all_bb();
        const moves = move_bb & not_all & target_sqs;

        if (from == 3 or from == 7) {
            log.debug("pq pieces: {s}", .{@tagName(piece)});
            log_bb(pieces, log.debug);

            log.debug("move_bb:", .{});
            log_bb(move_bb, log.debug);

            log.debug("not all occ:", .{});
            log_bb(not_all, log.debug);

            log.debug("pq moves:", .{});
            log_bb(moves, log.debug);
        }

        ml.add_quiets(from, moves, piece.with_ctm(b.ctm), MoveType.QUIET);
    }
}

fn piece_attack(ml: *MoveList, b: Board, comptime piece: Piece, comptime move_fn: fn (occ: BB, from: usize) BB, pin_sqs: BB, target_sqs: BB) void {
    var pieces = b.piece_bb(piece, b.ctm) & ~pin_sqs;
    const opp = b.col_bb(b.ctm.opp()) & target_sqs;

    while (pieces > 0) : (pieces &= pieces - 1) {
        const from: usize = @ctz(pieces);
        const moves: BB = move_fn(b.all_bb(), from) & opp;
        ml.add_caps(b, from, moves, piece.with_ctm(b.ctm), MoveType.CAP);
    }
}

pub fn knight_move(from: usize) BB {
    return knight_move_table[from];
}

fn knight_move_wrapper(unused_occ: BB, from: usize) BB {
    _ = unused_occ;
    return knight_move(from);
}

pub fn king_move(from: usize) BB {
    return king_move_table[from];
}

fn king_move_wrapper(unused_occ: BB, from: usize) BB {
    _ = unused_occ;
    return king_move(from);
}

pub fn pawn_att(sq: usize, ctm: Colour) BB {
    const mul: usize = if (ctm == Colour.WHITE) 0 else 1;
    return pawn_attack_table[sq + (64 * mul)];
}

fn king_castle(ml: *MoveList, b: Board) void {
    const from: usize = @ctz(b.piece_bb(Piece.KING, b.ctm));

    // if castle rights allow and no pieces are between king and rook
    const shift: u6 = @intCast(@intFromEnum(b.ctm) * 56);
    const kingside_mask: BB = @as(BB, 0x60) << shift;
    if (b.can_kingside() and (b.all_bb() & kingside_mask) == 0) {
        const mt = if (b.ctm == Colour.WHITE) MoveType.WKINGSIDE else MoveType.BKINGSIDE;
        ml.append(new_move(from, from + 2, Piece.KING.with_ctm(b.ctm), Piece.NONE, mt));
    }

    const queenside_mask: BB = @as(BB, 0xE) << shift;
    if (b.can_queenside() and (b.all_bb() & queenside_mask) == 0) {
        const mt = if (b.ctm == Colour.WHITE) MoveType.WQUEENSIDE else MoveType.BQUEENSIDE;
        ml.append(new_move(from, from - 2, Piece.KING.with_ctm(b.ctm), Piece.NONE, mt));
    }
}

fn gen_all_moves(ml: *MoveList, b: Board) void {
    piece_attack(ml, b, Piece.QUEEN, magic.lookup_queen, NO_SQUARES, ALL_SQUARES);
    piece_attack(ml, b, Piece.BISHOP, magic.lookup_bishop, NO_SQUARES, ALL_SQUARES);
    piece_attack(ml, b, Piece.ROOK, magic.lookup_rook, NO_SQUARES, ALL_SQUARES);
    piece_attack(ml, b, Piece.KNIGHT, knight_move_wrapper, NO_SQUARES, ALL_SQUARES);
    piece_attack(ml, b, Piece.KING, king_move_wrapper, NO_SQUARES, ALL_SQUARES);

    piece_quiet(ml, b, Piece.QUEEN, magic.lookup_queen, NO_SQUARES, ALL_SQUARES);
    piece_quiet(ml, b, Piece.BISHOP, magic.lookup_bishop, NO_SQUARES, ALL_SQUARES);
    piece_quiet(ml, b, Piece.ROOK, magic.lookup_rook, NO_SQUARES, ALL_SQUARES);
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

fn king_safe_target(b: Board, king_sq: usize) BB {
    // TODO is this the best way?
    var internal_b = b;
    var king_moves = king_move(king_sq);
    // remove the king while checking to find moving "away" from sliding pieces
    internal_b.toggle_all_pieces(internal_b.piece_bb(Piece.KING, internal_b.ctm));

    var safe: BB = 0;
    while (king_moves > 0) : (king_moves &= king_moves - 1) {
        const to: BB = @ctz(king_moves);

        if (internal_b.attackers_of_sq(to, internal_b.ctm.opp()) == 0) {
            safe |= square(to);
        }
    }

    // restore the king
    internal_b.toggle_all_pieces(internal_b.piece_bb(Piece.KING, internal_b.ctm));
    return safe;
}

fn pinned_sqs(b: Board, king_sq: usize) BB {
    var pinned: BB = 0;

    const all_occ = b.all_bb();
    const ctm_occ = b.col_bb(b.ctm);
    const opp = b.ctm.opp();

    const rook_queens: BB = b.piece_bb(Piece.ROOK, opp) | b.piece_bb(Piece.QUEEN, opp);
    var rq_pinners: BB =
        magic.lookup_rook_xray(all_occ, ctm_occ, king_sq) & rook_queens;

    while (rq_pinners > 0) : (rq_pinners &= rq_pinners - 1) {
        const from: BB = @ctz(rq_pinners);
        pinned |= magic.lookup_rook(all_occ, from);
    }

    const bishop_queens: BB = b.piece_bb(Piece.BISHOP, opp) | b.piece_bb(Piece.QUEEN, opp);
    var bq_pinners: BB = magic.lookup_bishop_xray(all_occ, ctm_occ, king_sq) &
        bishop_queens;

    while (bq_pinners > 0) : (bq_pinners &= bq_pinners - 1) {
        const from: BB = @ctz(bq_pinners);
        const lookup = magic.lookup_bishop(all_occ, from);
        pinned |= lookup;
    }

    if (pinned > 0) {
        const potential_pins = (magic.lookup_rook(all_occ, king_sq) | magic.lookup_bishop(all_occ, king_sq)) & ctm_occ;
        pinned &= potential_pins;
    }

    return pinned;
}

fn attacker_ray(b: Board, king_sq: usize, att_sq: usize) BB {
    if (king_sq % 8 == att_sq % 8 or king_sq / 8 == att_sq / 8) {
        return magic.lookup_rook(b.all_bb(), king_sq) &
            magic.lookup_rook(b.all_bb(), att_sq);
    } else {
        return magic.lookup_bishop(b.all_bb(), king_sq) &
            magic.lookup_bishop(b.all_bb(), att_sq);
    }
}

fn gen_check_moves(ml: *MoveList, b: Board) void {
    const king_sq: usize = @ctz(b.piece_bb(Piece.KING, b.ctm));

    const attackers = b.attackers_of_sq(king_sq, b.ctm.opp());
    const safe_moves = king_safe_target(b, king_sq);

    piece_quiet(ml, b, Piece.KING, king_move_wrapper, NO_SQUARES, safe_moves);
    piece_attack(ml, b, Piece.KING, king_move_wrapper, NO_SQUARES, safe_moves);

    // if there is more than one attacker there is nothing else to do
    if (attackers & (attackers - 1) > 0) {
        log.debug("more than one attacker", .{});
        return;
    }

    const pinned = pinned_sqs(b, king_sq);

    piece_attack(ml, b, Piece.QUEEN, magic.lookup_queen, pinned, attackers);
    piece_attack(ml, b, Piece.BISHOP, magic.lookup_bishop, pinned, attackers);
    piece_attack(ml, b, Piece.ROOK, magic.lookup_rook, pinned, attackers);
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

    piece_quiet(ml, b, Piece.QUEEN, magic.lookup_queen, pinned, att_ray);
    piece_quiet(ml, b, Piece.BISHOP, magic.lookup_bishop, pinned, att_ray);
    piece_quiet(ml, b, Piece.ROOK, magic.lookup_rook, pinned, att_ray);
    piece_quiet(ml, b, Piece.KNIGHT, knight_move_wrapper, pinned, att_ray);

    if (b.ctm == Colour.WHITE) wpawn_quiet(b, ml, pinned, att_ray) else bpawn_quiet(b, ml, pinned, att_ray);
}

pub fn gen_moves(ml: *MoveList, b: Board, checked: bool) void {
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

fn castle_is_legal(b: Board, sq1: usize, sq2: usize, c: Colour) bool {
    const can_sq1: bool = b.attackers_of_sq(sq1, c) == 0;
    const can_sq2: bool = b.attackers_of_sq(sq2, c) == 0;
    return can_sq1 and can_sq2;
}

// assumes the move has already been applied to the board
pub fn is_legal_move(b: Board, m: Move, checked: bool) bool {
    if (b.halfmove > 100) {
        log.debug("halfmove", .{});
        return false;
    }

    // checked has legal move gen and no casling is required
    if (checked) {
        return true;
    }

    // TODO check the transposition table to see if this board already exists

    // check if moved into check
    const ksq: usize = @ctz(b.piece_bb(Piece.KING, b.ctm.opp()));
    // TODO could be optimised (see rnr)
    if (b.attackers_of_sq(ksq, b.ctm) > 0) {
        log.debug("moved in check", .{});
        return false;
    }

    return switch (m.mt) {
        MoveType.WKINGSIDE => castle_is_legal(b, 5, 6, Colour.BLACK),
        MoveType.WQUEENSIDE => castle_is_legal(b, 3, 2, Colour.BLACK),
        MoveType.BKINGSIDE => castle_is_legal(b, 61, 62, Colour.WHITE),
        MoveType.BQUEENSIDE => castle_is_legal(b, 59, 58, Colour.WHITE),
        else => true,
    };
}
