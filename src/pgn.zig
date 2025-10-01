const std = @import("std");
const board = @import("board.zig");
const Board = board.Board;
const Piece = board.Piece;
const File = board.File;
const Rank = board.Rank;
const movegen = @import("movegen.zig");
const Move = movegen.Move;
const util = @import("util.zig");

fn alg_take_piece(alg: []const u8, ctm: board.Colour, piece: *Piece) ![]const u8 {
    const p = switch (alg[0]) {
        'K' => Piece.KING,
        'Q' => Piece.QUEEN,
        'R' => Piece.ROOK,
        'B' => Piece.BISHOP,
        'N' => Piece.KNIGHT,
        'a'...'h' => Piece.PAWN,
        else => {
            std.log.err("unknown piece in move '{s}'", .{alg});
            return error.UnknownAlgebraicPiece;
        },
    };

    piece.* = p.with_ctm(ctm);
    return alg[(if (p.is_pawn()) 0 else 1)..];
}

fn alg_take_disamb_file(alg: []const u8, file: *?File) []const u8 {
    if (alg.len <= 2) return alg;

    const f: ?File = switch (alg[0]) {
        'a' => .FA,
        'b' => .FB,
        'c' => .FC,
        'd' => .FD,
        'e' => .FE,
        'f' => .FF,
        'g' => .FG,
        'h' => .FH,
        else => null,
    };

    file.* = f;

    return alg[(if (f == null) 0 else 1)..];
}

fn alg_take_disamb_rank(alg: []const u8, rank: *?Rank) []const u8 {
    if (alg.len <= 2) return alg;

    const r: ?Rank = switch (alg[0]) {
        '1' => .R1,
        '2' => .R2,
        '3' => .R3,
        '4' => .R4,
        '5' => .R5,
        '6' => .R6,
        '7' => .R7,
        '8' => .R8,
        else => null,
    };

    rank.* = r;

    return alg[(if (r == null) 0 else 1)..];
}

fn alg_take_cap(alg: []const u8, cap: *bool) []const u8 {
    if (alg[0] == 'x') {
        cap.* = true;
        return alg[1..];
    }

    cap.* = false;
    return alg;
}

fn alg_take_to_sq(alg: []const u8, sq: *usize) ![]const u8 {
    sq.* = try util.sq_from_str(alg[0..2]);
    return alg[2..];
}

fn alg_is_castling(alg: []const u8, ctm: board.Colour) ?Move {
    const shift: usize = @intCast(@intFromEnum(ctm) * 56);
    if (std.mem.eql(u8, alg, "O-O")) {
        const mt: movegen.MoveType = if (ctm == .WHITE) .WKINGSIDE else .BKINGSIDE;
        return Move.new(4 + shift, 6 + shift, Piece.KING.with_ctm(ctm), .NONE, mt);
    }

    if (std.mem.eql(u8, alg, "O-O-O")) {
        const mt: movegen.MoveType = if (ctm == .WHITE) .WQUEENSIDE else .BQUEENSIDE;
        return Move.new(4 + shift, 2 + shift, Piece.KING.with_ctm(ctm), .NONE, mt);
    }

    return null;
}

pub fn algebraic_to_move(b: *const Board, algebraic: []const u8) !Move {
    if (alg_is_castling(algebraic, b.ctm)) |m| return m;

    var alg = algebraic;

    var piece: Piece = undefined;
    alg = try alg_take_piece(algebraic, b.ctm, &piece);

    var file: ?File = null;
    alg = alg_take_disamb_file(alg, &file);

    var rank: ?Rank = null;
    alg = alg_take_disamb_rank(alg, &rank);

    var cap = false;
    alg = alg_take_cap(alg, &cap);

    var to: usize = undefined;
    alg = try alg_take_to_sq(alg, &to);

    // TODO would be cool (and quicker) to only generate the moves for that specific piece
    var ml = movegen.MoveList.new(b, null);
    movegen.gen_piece_moves(&ml, piece);

    std.log.debug("in: {s}\npiece: {s}\nfile: {s}\nrank: {s}\ncap: {s}\nto: {d}\n", .{
        algebraic,
        @tagName(piece),
        if (file) |f| @tagName(f) else "none",
        if (rank) |r| @tagName(r) else "none",
        if (cap) "cap" else "quiet",
        to,
    });

    while (ml.next()) |m| {
        std.log.debug("trying move:", .{});
        m.log(std.log.debug);

        if (file) |f| if (board.square(m.from) & @intFromEnum(f) == 0) continue;
        if (rank) |r| if (board.square(m.from) & @intFromEnum(r) == 0) continue;
        if ((m.xpiece != .NONE) != cap) continue;
        if (m.to != to) continue;
        std.log.debug("matched!\n\n", .{});
        return m;
    }

    return error.FailedToConvAlgebraic;
}
