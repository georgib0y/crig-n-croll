const std = @import("std");
const log = std.log;

const movegen = @import("movegen.zig");
const MoveType = movegen.MoveType;
const Move = movegen.Move;
const magic = @import("magic.zig");
const util = @import("util.zig");

pub const BB = u64;

const CastleState = u8;

pub inline fn square(idx: usize) BB {
    const shift: u6 = @intCast(idx);
    const sq: BB = 1;
    return sq << shift;
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

    pub fn opp(self: Colour) Colour {
        return @enumFromInt(@intFromEnum(self) ^ 1);
    }
};

pub const Piece = enum(u8) {
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

    fn pieces() []const Piece {
        return std.meta.fields(Piece)[0..12];
    }

    fn is_rook_like(self: Piece) bool {
        return switch (self) {
            Piece.ROOK, Piece.ROOK_B, Piece.QUEEN, Piece.QUEEN_B => true,
            else => false,
        };
    }

    fn is_bishop_like(self: Piece) bool {
        return switch (self) {
            Piece.BISHOP, Piece.BISHOP_B, Piece.QUEEN, Piece.QUEEN_B => true,
            else => false,
        };
    }

    pub fn is_slider(self: Piece) bool {
        return switch (self) {
            Piece.PAWN, Piece.PAWN_B, Piece.KNIGHT, Piece.KNIGHT_B, Piece.KING, Piece.KING_B => false,
            else => true,
        };
    }
};

pub fn piece_from_char(c: u8) ?Piece {
    return switch (c) {
        'P' => Piece.PAWN,
        'p' => Piece.PAWN_B,
        'N' => Piece.KNIGHT,
        'n' => Piece.KNIGHT_B,
        'R' => Piece.ROOK,
        'r' => Piece.ROOK_B,
        'B' => Piece.BISHOP,
        'b' => Piece.BISHOP_B,
        'Q' => Piece.QUEEN,
        'q' => Piece.QUEEN_B,
        'K' => Piece.KING,
        'k' => Piece.KING_B,
        else => null,
    };
}

pub fn char_from_piece(p: Piece) u8 {
    return switch (p) {
        Piece.PAWN => 'P',
        Piece.PAWN_B => 'p',
        Piece.KNIGHT => 'N',
        Piece.KNIGHT_B => 'n',
        Piece.ROOK => 'R',
        Piece.ROOK_B => 'r',
        Piece.BISHOP => 'B',
        Piece.BISHOP_B => 'b',
        Piece.QUEEN => 'Q',
        Piece.QUEEN_B => 'q',
        Piece.KING => 'K',
        Piece.KING_B => 'k',
        Piece.NONE => '.',
    };
}

pub const UtilBB = enum { ALL_W, ALL_B, ALL };

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

    pub fn piece_bb(self: Board, p: Piece, c: ?Colour) BB {
        return self.pieces[@intFromEnum(p) + @intFromEnum(c orelse Colour.WHITE)];
    }

    pub fn col_bb(self: Board, c: Colour) BB {
        return self.util[@intFromEnum(c)];
    }

    pub fn all_bb(self: Board) BB {
        return self.util[@intFromEnum(UtilBB.ALL)];
    }

    pub fn toggle_piece(self: *Board, p: Piece, c: ?Colour, bb: BB) void {
        const idx = @intFromEnum(p) + @intFromEnum(c orelse Colour.WHITE);
        self.pieces[idx] ^= bb;
    }

    pub fn toggle_colour_pieces(self: *Board, c: Colour, bb: BB) void {
        self.util[@intFromEnum(c)] ^= bb;
    }

    pub fn toggle_all_pieces(self: *Board, bb: BB) void {
        self.util[@intFromEnum(UtilBB.ALL)] ^= bb;
    }

    pub fn get_piece(self: Board, sq: usize) Piece {
        const bb = square(sq);
        inline for (0..self.pieces.len) |i| {
            if (self.pieces[i] & bb > 0) {
                return @enumFromInt(i);
            }
        }

        return Piece.NONE;
    }

    pub fn can_kingside(self: Board) bool {
        const shift: u3 = (2 - 2 * @as(u3, @intCast(@intFromEnum(self.ctm))));
        return self.castling >> shift & 0x2 > 0;
    }

    pub fn can_queenside(self: Board) bool {
        const shift: u3 = (2 - 2 * @as(u3, @intCast(@intFromEnum(self.ctm))));
        return self.castling >> shift & 1 > 0;
    }

    pub fn attackers_of_sq(self: Board, sq: usize, attackers: Colour) BB {
        var atts: BB = 0;

        // add pawn attacks, need to get the inverted pawn attacsk for the attacking
        // colour as we are working backwards from sq
        atts |= movegen.pawn_att(sq, attackers.opp()) & self.piece_bb(Piece.PAWN, attackers);
        atts |= movegen.knight_move(sq) & self.piece_bb(Piece.KNIGHT, attackers);
        atts |= movegen.king_move(sq) & self.piece_bb(Piece.KING, attackers);

        const rq: BB = self.piece_bb(Piece.ROOK, attackers) | self.piece_bb(Piece.QUEEN, attackers);
        atts |= magic.lookup_rook(self.all_bb(), sq) & rq;

        const bq: BB = self.piece_bb(Piece.BISHOP, attackers) | self.piece_bb(Piece.QUEEN, attackers);
        atts |= magic.lookup_bishop(self.all_bb(), sq) & bq;

        return 0;
    }

    pub fn is_in_check(self: Board) bool {
        const king_sq: usize = @ctz(self.piece_bb(Piece.KING, self.ctm));
        return self.attackers_of_sq(king_sq, self.ctm.opp()) > 0;
    }

    fn set_castle_state(b: *Board, p: Piece, from: usize, to: usize) void {
        // WKINGSIDE 0b1000
        if ((p == Piece.KING or from == 7 or to == 7) and b.castling & 0x8 > 0) {
            b.castling &= 0x7; // 0b0111
        }

        // WQUEENSIDE 0b100
        if ((p == Piece.KING or from == 0 or to == 0) and b.castling & 0x4 > 0) {
            b.castling &= 0xB; // 0b1011
        }

        // BKINGSIDE 0b10
        if ((p == Piece.KING_B or from == 63 or to == 63) and b.castling & 0x2 > 0) {
            b.castling &= 0xD; // 0b1101
        }

        // BQUEENSIDE 0b1
        if ((p == Piece.KING_B or from == 56 or to == 56) and b.castling & 0x1 > 0) {
            b.castling &= 0xE; // 0b1110
        }
    }

    fn apply_quiet(self: *Board, p: Piece) void {
        switch (p) {
            Piece.PAWN, Piece.PAWN_B => self.halfmove = 0,
            else => return,
        }
    }

    fn apply_double(self: *Board, to: usize) void {
        const ep: usize = to - 8 + (@intFromEnum(self.ctm) * 16);
        self.ep = @intCast(ep);
    }

    fn apply_cap(self: *Board, to: usize, xpiece: Piece) void {
        const to_sq = square(to);
        self.toggle_piece(xpiece, null, to_sq);
        self.toggle_colour_pieces(self.ctm.opp(), to_sq);
        self.toggle_all_pieces(to_sq);
    }

    fn apply_castle(self: *Board, c: Colour, from: usize, to: usize) void {
        const from_to: BB = square(from) | square(to);
        self.toggle_piece(Piece.ROOK, c, from_to);
        self.toggle_colour_pieces(c, from_to);
        self.toggle_all_pieces(from_to);
    }

    fn apply_promo(self: *Board, xpiece: Piece, to: usize) void {
        // toggle pawn off and toggle the promo on
        self.toggle_piece(Piece.PAWN, self.ctm, square(to));
        self.toggle_piece(xpiece, null, square(to));
        self.halfmove = 0;
    }

    fn apply_promo_cap(self: *Board, mt: movegen.MoveType, xpiece: Piece, to: usize) void {
        const to_sq: BB = square(to);

        // N_PROMO_CAP (8) - 7 = [1], [1] * 2 + b.colour_to_move == 2 or 3 (knight
        // idx)
        // R_PROMO_CAP (9) - 7 = [2], [2] * 2 + b.colour_to_move == 4 or 5 (rook idx)
        // etc

        const promo_p: Piece = @enumFromInt((@intFromEnum(mt) - 7) * 2 + @intFromEnum(self.ctm));

        // toggle captured piece
        self.toggle_piece(xpiece, null, to_sq);
        self.toggle_colour_pieces(self.ctm.opp(), to_sq);

        // retoggle piece (as its been replaces by the capturer)
        self.toggle_all_pieces(to_sq);
        // toggle pawn off
        self.toggle_colour_pieces(self.ctm, to_sq);
        // toggle promo on
        self.toggle_piece(promo_p, null, to_sq);

        self.halfmove = 0;
    }

    fn apply_ep(self: *Board, to: usize) void {
        const ep: usize = to - 8 + (@intFromEnum(self.ctm) * 16);
        const ep_sq = square(ep);
        // toggle capture pawn off
        self.toggle_piece(Piece.PAWN, self.ctm.opp(), ep_sq);
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
            MoveType.BQUEENSIDE => self.apply_castle(Colour.WHITE, 56, 59),
            MoveType.PROMO => self.apply_promo(xpiece, to),
            MoveType.NPROMOCAP, MoveType.RPROMOCAP, MoveType.BPROMOCAP, MoveType.QPROMOCAP => self.apply_promo_cap(mt, xpiece, to),
            MoveType.EP => self.apply_ep(to),
        }
    }

    pub fn copy_make(self: Board, noalias dest: *Board, m: Move) void {
        dest.* = self;

        const from: usize = @intCast(m.from);
        const to: usize = @intCast(m.to);
        const piece: Piece = @enumFromInt(m.piece);
        const xpiece: Piece = @enumFromInt(m.xpiece);

        const from_to: BB = square(from) | square(to);

        dest.toggle_piece(piece, null, from_to);
        dest.toggle_colour_pieces(dest.ctm, from_to);
        dest.toggle_all_pieces(from_to);

        dest.set_castle_state(piece, from, to);

        dest.ep = 64;
        dest.halfmove += 1;

        dest.apply_move(to, piece, xpiece, m.mt);

        dest.ctm = self.ctm.opp();
    }

    pub fn log(self: Board, comptime log_fn: fn (comptime []const u8, anytype) void) void {
        util.log_board(self, log_fn);
    }

    pub fn display(self: Board, writer: anytype) !void {
        try util.display_board(self, writer);
    }
};

pub fn default_board() Board {
    const board = Board{
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
    };

    // TODO hash and eval

    return board;
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
        'w' => Colour.WHITE,
        'b' => Colour.BLACK,
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

    const halfmove_str = it.next() orelse return b;
    b.halfmove = std.fmt.parseInt(u8, halfmove_str, 10) catch return error.InvalidFenBadHalfmove;

    return b;
}
