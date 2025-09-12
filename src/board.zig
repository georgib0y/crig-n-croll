const std = @import("std");
const log = std.log;

const movegen = @import("movegen.zig");
const MoveType = movegen.MoveType;
const Move = movegen.Move;
const util = @import("util.zig");
const eval = @import("eval.zig");
const tt = @import("tt.zig");

pub const BB = u64;

pub const CastleState = u8;

pub fn square(idx: usize) BB {
    return @as(BB, 1) << @as(u6, @intCast(idx));
}

pub const File = enum(BB) {
    FA = 0x0101010101010101,
    FB = 0x0202020202020202,
    FC = 0x0404040404040404,
    FD = 0x0808080808080808,
    FE = 0x1010101010101010,
    FF = 0x2020202020202020,
    FG = 0x4040404040404040,
    FH = 0x8080808080808080,
};

pub const Rank = enum(BB) {
    R1 = 0x00000000000000FF,
    R2 = 0x000000000000FF00,
    R3 = 0x0000000000FF0000,
    R4 = 0x00000000FF000000,
    R5 = 0x000000FF00000000,
    R6 = 0x0000FF0000000000,
    R7 = 0x00FF000000000000,
    R8 = 0xFF00000000000000,
};

pub const Colour = enum(u8) {
    WHITE = 0,
    BLACK = 1,

    pub inline fn opp(self: Colour) Colour {
        return @enumFromInt(@intFromEnum(self) ^ 1);
    }
};

pub const Piece = enum(u4) {
    PAWN = 0,
    PAWN_B = 1,
    KNIGHT = 2,
    KNIGHT_B = 3,
    ROOK = 4,
    ROOK_B = 5,
    BISHOP = 6,
    BISHOP_B = 7,
    QUEEN = 8,
    QUEEN_B = 9,
    KING = 10,
    KING_B = 11,
    NONE,

    pub fn idx(self: Piece, c: Colour) usize {
        return @intFromEnum(self) + @intFromEnum(c);
    }

    pub fn with_ctm(self: Piece, c: Colour) Piece {
        return @enumFromInt(self.idx(c));
    }

    pub fn colour_pieces(c: Colour) [6]Piece {
        if (c == .WHITE) {
            return .{ .PAWN, .KNIGHT, .ROOK, .BISHOP, .QUEEN, .KING };
        } else {
            return .{ .PAWN_B, .KNIGHT_B, .ROOK_B, .BISHOP_B, .QUEEN_B, .KING_B };
        }
    }

    pub fn pieces() [12]Piece {
        var p: [12]Piece = undefined;
        for (0..12) |i| {
            p[i] = @enumFromInt(i);
        }
        return p;
    }

    pub fn is_rook_like(self: Piece) bool {
        return switch (self) {
            .ROOK, .ROOK_B, .QUEEN, .QUEEN_B => true,
            else => false,
        };
    }

    pub fn is_bishop_like(self: Piece) bool {
        return switch (self) {
            .BISHOP, .BISHOP_B, .QUEEN, .QUEEN_B => true,
            else => false,
        };
    }

    pub fn is_slider(self: Piece) bool {
        return switch (self) {
            .PAWN, .PAWN_B, .KNIGHT, .KNIGHT_B, .KING, .KING_B => false,
            else => true,
        };
    }
};

pub fn piece_from_char(c: u8) ?Piece {
    return switch (c) {
        'P' => .PAWN,
        'p' => .PAWN_B,
        'N' => .KNIGHT,
        'n' => .KNIGHT_B,
        'R' => .ROOK,
        'r' => .ROOK_B,
        'B' => .BISHOP,
        'b' => .BISHOP_B,
        'Q' => .QUEEN,
        'q' => .QUEEN_B,
        'K' => .KING,
        'k' => .KING_B,
        else => null,
    };
}

pub fn char_from_piece(p: Piece) u8 {
    return switch (p) {
        .PAWN => 'P',
        .PAWN_B => 'p',
        .KNIGHT => 'N',
        .KNIGHT_B => 'n',
        .ROOK => 'R',
        .ROOK_B => 'r',
        .BISHOP => 'B',
        .BISHOP_B => 'b',
        .QUEEN => 'Q',
        .QUEEN_B => 'q',
        .KING => 'K',
        .KING_B => 'k',
        .NONE => '.',
    };
}

pub const Board = struct {
    pieces: [12]BB,
    util: [3]BB,
    ctm: Colour,
    castling: CastleState,
    ep: u8,
    halfmove: u8,
    hash: u64,
    mg_val: i32,
    eg_val: i32,
    phase: u8,

    pub inline fn piece_bb(self: *const Board, p: Piece, c: Colour) BB {
        const pidx: usize = @intFromEnum(p);
        const cidx: usize = @intFromEnum(c);
        const idx: usize = pidx + cidx;
        return self.pieces[idx];
    }

    pub fn col_bb(self: *const Board, c: Colour) BB {
        return self.util[@intFromEnum(c)];
    }

    pub inline fn all_bb(self: *const Board) BB {
        return self.util[2];
    }

    pub fn toggle_piece_on(self: *Board, p: Piece, sq: usize) void {
        self.pieces[@intFromEnum(p)] ^= square(sq);
        self.hash ^= tt.piece_zobrist(p, sq);

        self.mg_val += eval.MAT_SCORES[@intFromEnum(p)];
        self.mg_val += eval.MID_PST[@intFromEnum(p)][sq];
        self.eg_val += eval.MAT_SCORES[@intFromEnum(p)];
        self.eg_val += eval.END_PST[@intFromEnum(p)][sq];

        self.phase += eval.PIECE_PHASE_VAL[@intFromEnum(p)];
    }

    pub fn toggle_piece_off(self: *Board, p: Piece, sq: usize) void {
        self.pieces[@intFromEnum(p)] ^= square(sq);
        self.hash ^= tt.piece_zobrist(p, sq);

        self.mg_val -= eval.MAT_SCORES[@intFromEnum(p)];
        self.mg_val -= eval.MID_PST[@intFromEnum(p)][sq];
        self.eg_val -= eval.MAT_SCORES[@intFromEnum(p)];
        self.eg_val -= eval.END_PST[@intFromEnum(p)][sq];

        self.phase -= eval.PIECE_PHASE_VAL[@intFromEnum(p)];
    }

    pub fn toggle_colour_pieces(self: *Board, c: Colour, bb: BB) void {
        self.util[@intFromEnum(c)] ^= bb;
    }

    pub fn toggle_all_pieces(self: *Board, bb: BB) void {
        self.util[2] ^= bb;
    }

    pub fn get_piece(self: *const Board, sq: usize) Piece {
        const bb = square(sq);
        for (0..self.pieces.len) |i| {
            if (self.pieces[i] & bb > 0) {
                return @enumFromInt(i);
            }
        }

        return Piece.NONE;
    }

    // TODO 10 is just a wild guess
    pub fn is_in_endgame(self: *const Board) bool {
        return self.phase <= 10;
    }

    // pub fn _get_piece(self: *const Board, sq: usize) Piece {}

    pub fn can_kingside(self: *const Board) bool {
        const shift: u3 = (2 - 2 * @as(u3, @intCast(@intFromEnum(self.ctm))));
        return (self.castling >> shift) & 0x2 > 0;
    }

    pub fn can_queenside(self: *const Board) bool {
        const shift: u3 = (2 - 2 * @as(u3, @intCast(@intFromEnum(self.ctm))));
        return (self.castling >> shift) & 1 > 0;
    }

    pub fn attackers_of_sq(self: *const Board, sq: usize, attackers: Colour) BB {
        var atts: BB = 0;
        // add pawn attacks, need to get the inverted pawn attacsk for the attacking
        // colour as we are working backwards from sq
        atts |= movegen.pawn_att(sq, attackers.opp()) & self.piece_bb(.PAWN, attackers);
        atts |= movegen.knight_move(sq) & self.piece_bb(.KNIGHT, attackers);
        atts |= movegen.king_move(sq) & self.piece_bb(.KING, attackers);

        const rq: BB = self.piece_bb(.ROOK, attackers) | self.piece_bb(.QUEEN, attackers);
        atts |= movegen.lookup_rook(self.all_bb(), sq) & rq;

        const bq: BB = self.piece_bb(.BISHOP, attackers) | self.piece_bb(.QUEEN, attackers);
        atts |= movegen.lookup_bishop(self.all_bb(), sq) & bq;

        return atts;
    }

    pub fn is_in_check(self: *const Board) bool {
        const king_sq: usize = @ctz(self.piece_bb(.KING, self.ctm));
        return self.attackers_of_sq(king_sq, self.ctm.opp()) > 0;
    }

    fn set_castle_state(b: *Board, p: Piece, from: usize, to: usize) void {
        // WKINGSIDE 0b1000
        if ((p == .KING or from == 7 or to == 7) and b.castling & 0b1000 > 0) {
            b.castling &= 0b0111;
            b.hash ^= tt.castle_zobrist(.WKS);
        }

        // WQUEENSIDE 0b100
        if ((p == .KING or from == 0 or to == 0) and b.castling & 0b0100 > 0) {
            b.castling &= 0b1011;
            b.hash ^= tt.castle_zobrist(.WQS);
        }

        // BKINGSIDE 0b10
        if ((p == .KING_B or from == 63 or to == 63) and b.castling & 0b0010 > 0) {
            b.castling &= 0b1101;
            b.hash ^= tt.castle_zobrist(.BKS);
        }

        // BQUEENSIDE 0b1
        if ((p == .KING_B or from == 56 or to == 56) and b.castling & 0b0001 > 0) {
            b.castling &= 0b1110;
            b.hash ^= tt.castle_zobrist(.BQS);
        }
    }

    fn apply_quiet(self: *Board, p: Piece) void {
        self.halfmove = self.halfmove * @as(u8, @intFromBool(@intFromEnum(p) < 2));
    }

    fn apply_double(self: *Board, to: usize) void {
        const ep: usize = to - 8 + (@intFromEnum(self.ctm) * 16);
        self.ep = @intCast(ep);
        self.hash ^= tt.ep_zobrist(ep);
    }

    fn apply_cap(self: *Board, to: usize, xpiece: Piece) void {
        const to_sq = square(to);
        self.toggle_piece_off(xpiece, to);
        self.toggle_colour_pieces(self.ctm.opp(), to_sq);
        self.toggle_all_pieces(to_sq);
    }

    fn apply_castle(self: *Board, c: Colour, from: usize, to: usize) void {
        const from_to: BB = square(from) | square(to);
        self.toggle_piece_off(Piece.ROOK.with_ctm(c), from);
        self.toggle_piece_on(Piece.ROOK.with_ctm(c), to);
        self.toggle_colour_pieces(c, from_to);
        self.toggle_all_pieces(from_to);
    }

    fn apply_promo(self: *Board, xpiece: Piece, to: usize) void {
        // toggle pawn off and toggle the promo on
        self.toggle_piece_off(Piece.PAWN.with_ctm(self.ctm), to);
        self.toggle_piece_on(xpiece, to);
        self.halfmove = 0;
    }

    fn apply_promo_cap(self: *Board, mt: movegen.MoveType, xpiece: Piece, to: usize) void {
        const to_sq: BB = square(to);
        const promo_p: Piece = @enumFromInt((@intFromEnum(mt) - 7) * 2);

        // toggle captured piece
        self.toggle_piece_off(xpiece, to);
        self.toggle_colour_pieces(self.ctm.opp(), to_sq);

        // retoggle piece (as its been replaces by the capturer)
        self.toggle_all_pieces(to_sq);

        // toggle pawn off
        self.toggle_piece_off(Piece.PAWN.with_ctm(self.ctm), to);

        // toggle promo on
        self.toggle_piece_on(promo_p.with_ctm(self.ctm), to);

        self.halfmove = 0;
    }

    fn apply_ep(self: *Board, to: usize) void {
        const ep: usize = to - 8 + (@intFromEnum(self.ctm) * 16);
        const ep_sq = square(ep);
        // toggle capture pawn off
        self.toggle_piece_off(Piece.PAWN.with_ctm(self.ctm.opp()), ep);
        self.toggle_colour_pieces(self.ctm.opp(), ep_sq);
        self.toggle_all_pieces(ep_sq);

        self.halfmove = 0;
    }

    fn apply_move(self: *Board, to: usize, piece: Piece, xpiece: Piece, mt: MoveType) void {
        switch (mt) {
            MoveType.QUIET => self.apply_quiet(piece),
            MoveType.DOUBLE => self.apply_double(to),
            MoveType.CAP => self.apply_cap(to, xpiece),
            MoveType.WKINGSIDE => self.apply_castle(Colour.WHITE, 7, 5),
            MoveType.WQUEENSIDE => self.apply_castle(Colour.WHITE, 0, 3),
            MoveType.BKINGSIDE => self.apply_castle(Colour.BLACK, 63, 61),
            MoveType.BQUEENSIDE => self.apply_castle(Colour.BLACK, 56, 59),
            MoveType.PROMO => self.apply_promo(xpiece, to),
            MoveType.NPROMOCAP, MoveType.RPROMOCAP, MoveType.BPROMOCAP, MoveType.QPROMOCAP => self.apply_promo_cap(mt, xpiece, to),
            MoveType.EP => self.apply_ep(to),
        }
    }

    pub fn make_null(self: *Board) void {
        self.ctm = self.ctm.opp();
        self.halfmove += 1;
    }

    pub fn unmake_null(self: *Board) void {
        self.ctm = self.ctm.opp();
        self.halfmove -= 1;
    }

    pub fn copy_make(self: *const Board, dest: *Board, m: Move) void {
        // cannot copy into itself
        std.debug.assert(self != dest);
        dest.* = self.*;

        const from: usize = @intCast(m.from);
        const to: usize = @intCast(m.to);
        const piece: Piece = m.piece;
        const xpiece: Piece = m.xpiece;

        const from_to: BB = square(from) | square(to);

        dest.toggle_piece_off(piece, from);
        dest.toggle_piece_on(piece, to);
        dest.toggle_colour_pieces(dest.ctm, from_to);
        dest.toggle_all_pieces(from_to);

        dest.set_castle_state(piece, from, to);

        // unset the ep from the hash
        dest.hash ^= tt.ep_zobrist(dest.ep) * @as(u64, @intFromBool(dest.ep < 64));
        dest.ep = 64;
        dest.halfmove += 1;

        dest.apply_move(to, piece, xpiece, m.mt);

        dest.ctm = self.ctm.opp();
        dest.hash ^= tt.colour_zobrist();
    }

    pub fn log(self: Board, comptime log_fn: fn (comptime []const u8, anytype) void) void {
        util.log_board(self, log_fn);
    }

    pub fn display(self: Board, w: *std.Io.Writer) !void {
        try util.display_board(self, w);
    }
};

pub fn default_board() Board {
    var board = Board{
        .pieces = .{
            0x000000000000FF00, // wp 0
            0x00FF000000000000, // bp 1
            0x0000000000000042, // wn 2
            0x4200000000000000, // bn 3
            0x0000000000000081, // wr 4
            0x8100000000000000, // br 5
            0x0000000000000024, // wb 6
            0x2400000000000000, // bb 7
            0x0000000000000008, // wq 8
            0x0800000000000000, // bq 9
            0x0000000000000010, // wk 10
            0x1000000000000000, // bk 11
        },
        .util = .{
            0x000000000000FFFF, // white
            0xFFFF000000000000, // black
            0xFFFF00000000FFFF, // all
        },
        .ctm = Colour.WHITE,
        .castling = 0xFF,
        .halfmove = 0,
        .ep = 64,
        .hash = undefined,
        .mg_val = undefined,
        .eg_val = undefined,
        .phase = undefined,
    };

    // TODO hash and eval

    board.hash = tt.hash_board(&board);
    board.mg_val, board.eg_val, board.phase = eval.eval_board_full(&board);
    return board;
}

pub fn cmp_boards(b1: *const Board, b2: *const Board) bool {
    for (b1.pieces, b2.pieces) |p1, p2| {
        if (p1 != p2) return false;
    }
    for (b1.util, b2.util) |util1, util2| {
        if (util1 != util2) return false;
    }

    if (b1.ctm != b2.ctm) return false;
    if (b1.castling != b2.castling) return false;
    if (b1.ep != b2.ep) return false;
    if (b1.hash != b2.hash) return false;

    return true;
}

// assums pieces and util have been zeroed
fn parse_pieces(pieces_str: []const u8, pieces: []BB, util_bb: []BB) !void {
    var it = std.mem.splitScalar(u8, pieces_str, '/');

    // has to be signed so that the -8 can go under 0
    var row_start: isize = 56;
    while (row_start >= 0) : (row_start -= 8) {
        const row_str = it.next() orelse return error.InvalidPiecesNotEnoughRows;

        var sq: usize = @intCast(row_start);
        for (row_str) |c| {
            if (piece_from_char(c)) |piece| {
                pieces[@intFromEnum(piece)] ^= square(sq);
                sq += 1;
                continue;
            }

            if (c < '1' or c > '8') {
                return error.InvalidPiecesInvalidChar;
            }

            sq += @as(usize, c - '0');
        }
    }

    for (0..pieces.len) |i| {
        // add to white or black util board
        util_bb[i & 1] |= pieces[i];

        // add to all
        util_bb[2] |= pieces[i];
    }
}

fn parse_ctm(ctm_str: []const u8) !Colour {
    if (ctm_str.len != 1) {
        return error.InvalidCtmLen;
    }

    return switch (ctm_str[0]) {
        'w' => .WHITE,
        'b' => .BLACK,
        else => error.InvalidCtmChar,
    };
}

fn parse_castling(castle_str: []const u8) !CastleState {
    var cs: CastleState = 0;

    for (castle_str) |c| {
        switch (c) {
            'K' => cs |= 0x8,
            'Q' => cs |= 0x4,
            'k' => cs |= 0x2,
            'q' => cs |= 0x1,
            '-' => return 0,
            else => return error.InvalidCastleState,
        }
    }

    return cs;
}

fn sq_from_str(sq_str: []const u8) !usize {
    if (sq_str.len != 2) {
        return error.InvalidSquareStringLen;
    }

    const file = sq_str[0];
    const rank = sq_str[1];

    if (file < 'a' or file > 'h' or rank < '1' or rank > '8') {
        return error.InvalidSquareStringChar;
    }

    return @as(usize, (rank - '1') * 8 + (file - 'a'));
}

fn parse_ep(ep_str: []const u8) !u8 {
    if (ep_str[0] == '-') {
        return 64;
    }

    return @intCast(try sq_from_str(ep_str));
}

pub fn board_from_fen(fen: []const u8) !Board {
    var b = std.mem.zeroes(Board);
    // TODO defer hash and val funcs

    var it = std.mem.splitScalar(u8, std.mem.trim(u8, fen, " \n"), ' ');

    const pieces_str = it.next() orelse return error.InvalidFenNoPieces;
    try parse_pieces(pieces_str, &b.pieces, &b.util);

    const ctm_str = it.next() orelse return error.InvalidFenNoCtm;
    b.ctm = try parse_ctm(ctm_str);

    const castle_str = it.next() orelse return error.InvalidFenNoCastle;
    b.castling = try parse_castling(castle_str);

    const ep_str = it.next() orelse return error.InvalidFenNoEp;
    b.ep = try parse_ep(ep_str);

    b.hash = tt.hash_board(&b);
    b.mg_val, b.eg_val, b.phase = eval.eval_board_full(&b);

    const halfmove_str = it.next() orelse return b;
    b.halfmove = std.fmt.parseInt(u8, halfmove_str, 10) catch return error.InvalidFenBadHalfmove;

    return b;
}
