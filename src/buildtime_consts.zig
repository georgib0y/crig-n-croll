const std = @import("std");

const board = @import("board.zig");
const BB = board.BB;
const square = board.square;
const File = board.File;
const Rank = board.Rank;

// const RANDOM_SEED: u64 = 7252092290257123456;
const RANDOM_SEED: u64 = 16013208288946525155;
var rng = std.Random.DefaultPrng.init(RANDOM_SEED);

var zobrist: [781]u64 = undefined;

fn init_zobrist() void {
    for (0..zobrist.len) |i| {
        zobrist[i] = rng.next();
    }
}

// these are redeclared from magic.zig to avoid weird cycles
const SquareMagic = struct { mask: BB, magic: u64 };
const RSHIFT = 12; // !
const BSHIFT = 9;

var rook_magics: [64]SquareMagic = undefined;
var bishop_magics: [64]SquareMagic = undefined;

var bishop_move_table: [64][512]BB = undefined;
var rook_move_table: [64][4096]BB = undefined;

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
        bb |= square(i) >> 8;
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

// stolen from magic.zig for super_moves
fn lookup_bishop(occ: BB, sq: usize) BB {
    var o = occ;
    o &= bishop_magics[sq].mask;
    o = @mulWithOverflow(o, bishop_magics[sq].magic).@"0";
    o >>= 64 - BSHIFT;
    return bishop_move_table[sq][o];
}

fn lookup_rook(occ: BB, sq: usize) BB {
    var o = occ;
    o &= rook_magics[sq].mask;
    o = @mulWithOverflow(o, rook_magics[sq].magic).@"0";
    o >>= 64 - RSHIFT;
    return rook_move_table[sq][o];
}

var super_moves: [64]BB = undefined;
// requires all other moves and magics to be initialised
pub fn init_super_moves() void {
    for (0..64) |sq| {
        var m: BB = 0;
        m |= knight_move_table[sq];
        m |= king_move_table[sq];
        m |= lookup_rook(0, sq);
        m |= lookup_bishop(0, sq);
        super_moves[sq] = m;
    }
}

fn write_int_array(w: anytype, comptime T: type, a: []const T, name: []const u8) !void {
    try std.fmt.format(w, "pub const {s}: [{d}]{s} = .{{\n", .{ name, a.len, @typeName(T) });
    for (a) |i| {
        try std.fmt.format(w, "\t{d},\n", .{i});
    }
    try std.fmt.format(w, "}};\n", .{});
}

fn write_mt_array(w: anytype, s: comptime_int, a: [][s]BB, name: []const u8) !void {
    try std.fmt.format(w, "pub const {s}: [{d}][{d}]BB = .{{\n", .{ name, a.len, a[0].len });
    for (a) |sqs| {
        try std.fmt.format(w, "\t.{{", .{});
        for (sqs) |sq| {
            try std.fmt.format(w, "0x{X}, ", .{sq});
        }
        try std.fmt.format(w, "}},\n", .{});
    }
    try std.fmt.format(w, "}};\n", .{});
}

fn write_sq_mag(w: anytype, a: []SquareMagic, name: []const u8) !void {
    try std.fmt.format(w, "pub const {s}: [{d}]SquareMagic = .{{\n", .{ name, a.len });
    for (a) |m| {
        try std.fmt.format(w, "\t.{{ .mask = 0x{X}, .magic = 0x{X}}},\n", .{ m.mask, m.magic });
    }
    try std.fmt.format(w, "}};\n", .{});
}

pub fn main() !void {
    try gen_magics();

    init_zobrist();

    init_pawn_attacks();
    init_knight_move_table();
    init_king_move_table();
    init_super_moves();

    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const args = try std.process.argsAlloc(arena);

    const output_file_path = args[1];

    var output_file = std.fs.cwd().createFile(output_file_path, .{}) catch |err| {
        std.zig.fatal("could not open {s} : {s}", .{ output_file_path, @errorName(err) });
    };
    defer output_file.close();

    const w = output_file.writer();

    try std.fmt.format(w, "const BB = u64;\n", .{});
    try std.fmt.format(w, "const SquareMagic = struct {{ mask: BB, magic: u64 }};\n", .{});

    try write_int_array(w, u64, &zobrist, "zobrist");

    try write_int_array(w, BB, &pawn_attack_table, "pawn_attack_table");
    try write_int_array(w, BB, &knight_move_table, "knight_move_table");
    try write_int_array(w, BB, &king_move_table, "king_move_table");
    try write_int_array(w, BB, &super_moves, "super_moves");

    try write_int_array(w, i16, &WPAWN_MID_PST, "WPAWN_MID_PST");
    try write_int_array(w, i16, &WPAWN_END_PST, "WPAWN_END_PST");
    try write_int_array(w, i16, &WKNIGHT_MID_PST, "WKNIGHT_MID_PST");
    try write_int_array(w, i16, &WKNIGHT_END_PST, "WKNIGHT_END_PST");
    try write_int_array(w, i16, &WBISHOP_MID_PST, "WBISHOP_MID_PST");
    try write_int_array(w, i16, &WBISHOP_END_PST, "WBISHOP_END_PST");
    try write_int_array(w, i16, &WROOK_MID_PST, "WROOK_MID_PST");
    try write_int_array(w, i16, &WROOK_END_PST, "WROOK_END_PST");
    try write_int_array(w, i16, &WQUEEN_MID_PST, "WQUEEN_MID_PST");
    try write_int_array(w, i16, &WQUEEN_END_PST, "WQUEEN_END_PST");
    try write_int_array(w, i16, &WKING_MID_PST, "WKING_MID_PST");
    try write_int_array(w, i16, &WKING_END_PST, "WKING_END_PST");

    try write_int_array(w, i16, &BPAWN_MID_PST, "BPAWN_MID_PST");
    try write_int_array(w, i16, &BPAWN_END_PST, "BPAWN_END_PST");
    try write_int_array(w, i16, &BKNIGHT_MID_PST, "BKNIGHT_MID_PST");
    try write_int_array(w, i16, &BKNIGHT_END_PST, "BKNIGHT_END_PST");
    try write_int_array(w, i16, &BBISHOP_MID_PST, "BBISHOP_MID_PST");
    try write_int_array(w, i16, &BBISHOP_END_PST, "BBISHOP_END_PST");
    try write_int_array(w, i16, &BROOK_MID_PST, "BROOK_MID_PST");
    try write_int_array(w, i16, &BROOK_END_PST, "BROOK_END_PST");
    try write_int_array(w, i16, &BQUEEN_MID_PST, "BQUEEN_MID_PST");
    try write_int_array(w, i16, &BQUEEN_END_PST, "BQUEEN_END_PST");
    try write_int_array(w, i16, &BKING_MID_PST, "BKING_MID_PST");
    try write_int_array(w, i16, &BKING_END_PST, "BKING_END_PST");

    try write_sq_mag(w, &rook_magics, "rook_magics");
    try write_sq_mag(w, &bishop_magics, "bishop_magics");

    try write_mt_array(w, 4096, &rook_move_table, "rook_move_table");
    try write_mt_array(w, 512, &bishop_move_table, "bishop_move_table");

    return std.process.cleanExit();
}

// the following is heavily inspired by https://www.chessprogramming.org/Looking_for_Magics

const MAGIC_ITERS: usize = 1000000000;

fn random_magic() u64 {
    return rng.next() & rng.next() & rng.next(); // fewer bits are better apparently
}

fn pop_bit(bb: BB) struct { usize, BB } {
    const lz = @clz(bb);
    const idx = if (lz == 64) 0 else 63 - lz;
    return .{ idx, bb & ~square(idx) };
}

fn bb_from_int(variation: usize, bits: usize, mask: BB) BB {
    var m = mask;
    var j: usize = 0;

    var bb: BB = 0;
    for (0..bits) |i| {
        j, m = pop_bit(m);
        if ((variation & square(i)) > 0) {
            bb |= square(j);
        }
    }

    return bb;
}

fn rmask(sq: usize) BB {
    const rank: i32 = @intCast(sq / 8);
    const file: i32 = @intCast(sq % 8);

    var bb: BB = 0;

    var r = rank + 1;
    while (r <= 6) : (r += 1) {
        bb |= square(@intCast(file + r * 8));
    }

    r = rank - 1;
    while (r >= 1) : (r -= 1) {
        bb |= square(@intCast(file + r * 8));
    }

    var f = file + 1;
    while (f <= 6) : (f += 1) {
        bb |= square(@intCast(rank * 8 + f));
    }

    f = file - 1;
    while (f >= 1) : (f -= 1) {
        bb |= square(@intCast(rank * 8 + f));
    }

    return bb;
}

fn bmask(sq: usize) BB {
    const rank = sq / 8;
    const file = sq % 8;

    var bb: BB = 0;

    var r = rank + 1;
    var f = file + 1;
    while (r <= 6 and f <= 6) : ({
        r += 1;
        f += 1;
    }) {
        bb |= square(f + r * 8);
    }

    r = rank + 1;
    f = if (file == 0) 0 else file - 1;
    while (r <= 6 and f >= 1) : ({
        r += 1;
        f -= 1;
    }) {
        bb |= square(f + r * 8);
    }

    r = if (rank == 0) 0 else rank - 1;
    f = file + 1;
    while (r >= 1 and f <= 6) : ({
        r -= 1;
        f += 1;
    }) {
        bb |= square(f + r * 8);
    }

    r = if (rank == 0) 0 else rank - 1;
    f = if (file == 0) 0 else file - 1;
    while (r >= 1 and f >= 1) : ({
        r -= 1;
        f -= 1;
    }) {
        bb |= square(f + r * 8);
    }

    return bb;
}

fn ratt(sq: usize, blockers: BB) BB {
    const rank: i32 = @intCast(sq / 8);
    const file: i32 = @intCast(sq % 8);

    var bb: BB = 0;

    var r = rank + 1;
    while (r <= 7) : (r += 1) {
        bb |= square(@intCast(file + r * 8));
        if (blockers & square(@intCast(file + r * 8)) > 0) break;
    }

    r = rank - 1;
    while (r >= 0) : (r -= 1) {
        bb |= square(@intCast(file + r * 8));
        if (blockers & square(@intCast(file + r * 8)) > 0) break;
    }

    var f = file + 1;
    while (f <= 7) : (f += 1) {
        bb |= square(@intCast(rank * 8 + f));
        if (blockers & square(@intCast(rank * 8 + f)) > 0) break;
    }

    f = file - 1;
    while (f >= 0) : (f -= 1) {
        bb |= square(@intCast(rank * 8 + f));
        if (blockers & square(@intCast(rank * 8 + f)) > 0) break;
    }

    return bb;
}

fn batt(sq: usize, blockers: BB) BB {
    const rank: i32 = @intCast(sq / 8);
    const file: i32 = @intCast(sq % 8);

    var bb: BB = 0;

    var r = rank + 1;
    var f = file + 1;
    while (r <= 7 and f <= 7) : ({
        r += 1;
        f += 1;
    }) {
        bb |= square(@intCast(f + r * 8));
        if (blockers & square(@intCast(r * 8 + f)) > 0) break;
    }

    r = rank + 1;
    f = file - 1;
    while (r <= 7 and f >= 0) : ({
        r += 1;
        f -= 1;
    }) {
        bb |= square(@intCast(f + r * 8));
        if (blockers & square(@intCast(r * 8 + f)) > 0) break;
    }

    r = rank - 1;
    f = file + 1;
    while (r >= 0 and f <= 7) : ({
        r -= 1;
        f += 1;
    }) {
        bb |= square(@intCast(f + r * 8));
        if (blockers & square(@intCast(r * 8 + f)) > 0) break;
    }

    r = rank - 1;
    f = file - 1;
    while (r >= 0 and f >= 0) : ({
        r -= 1;
        f -= 1;
    }) {
        bb |= square(@intCast(f + r * 8));
        if (blockers & square(@intCast(r * 8 + f)) > 0) break;
    }

    return bb;
}

fn magic_idx(bb: BB, magic: u64, comptime bits: comptime_int) usize {
    const mul: usize = @mulWithOverflow(bb, magic).@"0";
    return mul >> @intCast(64 - bits);
}

fn gen_magic(move_table: []BB, comptime sq: comptime_int, comptime bits: comptime_int, comptime is_rook: bool) !SquareMagic {
    const mask = if (is_rook) rmask(sq) else bmask(sq);
    const mask_bits = @popCount(mask);

    var bitboards: [4096]BB = undefined;
    var moves: [4096]BB = undefined;
    for (0..square(mask_bits)) |i| {
        bitboards[i] = bb_from_int(i, bits, mask);
        moves[i] = if (is_rook) ratt(sq, bitboards[i]) else batt(sq, bitboards[i]);
    }

    var used: [4096]BB = undefined;
    outter: for (0..MAGIC_ITERS) |_| {
        const magic = random_magic();
        // some optimisation, apparently magics are more likely when there are a lot of high bits
        if (@popCount((@mulWithOverflow(mask, magic).@"0")) < 6) continue;

        for (0..4096) |i| used[i] = 0;

        for (0..square(mask_bits)) |i| {
            const idx = magic_idx(bitboards[i], magic, bits);
            if (used[idx] == 0) used[idx] = moves[i];
            if (used[idx] != moves[i]) {
                // if the idxes double up and are not the same moves then try the next magic
                continue :outter;
            }
        }

        for (0..move_table.len) |i| {
            move_table[i] = used[i];
        }
        return .{ .mask = mask, .magic = magic };
    }

    return error.FailedToFindMagic;
}

pub fn gen_magics() !void {
    inline for (0..64) |sq| {
        rook_magics[sq] = try gen_magic(&rook_move_table[sq], sq, RSHIFT, true);
        bishop_magics[sq] = try gen_magic(&bishop_move_table[sq], sq, BSHIFT, false);
    }
}

const WPAWN_MID_PST: [64]i16 = .{
    0,   0,   0,  0,  0,  0,   0,  0,   -35, -1, -20, -23, -15, 24, 38, -22, -26, -4, -4, -10, 3,  3,  33, -12,
    -27, -2,  -5, 12, 17, 6,   10, -25, -14, 13, 6,   21,  23,  12, 17, -23, -6,  7,  26, 31,  65, 56, 25, -20,
    98,  134, 61, 95, 68, 126, 34, -11, 0,   0,  0,   0,   0,   0,  0,  0,
};

const WPAWN_END_PST: [64]i16 = .{
    0,  0,  0, 0,  0,  0,  0,  0, 13, 8, 8,  10, 13, 0,   2,  -7, 4,  7,  -6, 1,  0,   -5,  -1,  -8,  13,  9,   -3,  -7,
    -7, -8, 3, -1, 32, 24, 13, 5, -2, 4, 17, 17, 94, 100, 85, 67, 56, 53, 82, 84, 178, 173, 158, 134, 147, 132, 165, 187,
    0,  0,  0, 0,  0,  0,  0,  0,
};

const WKNIGHT_MID_PST: [64]i16 = .{
    -105, -21, -58, -33,  -17, -28, -19, -23, -29, -53, -12, -3, -1, 18, -14, -19, -23,  -9,  12,  10,
    19,   17,  25,  -16,  -13, 4,   16,  13,  28,  19,  21,  -8, -9, 17, 19,  53,  37,   69,  18,  22,
    -47,  60,  37,  65,   84,  129, 73,  44,  -73, -41, 72,  36, 23, 62, 7,   -17, -167, -89, -34, -49,
    61,   -97, -15, -107,
};

const WKNIGHT_END_PST: [64]i16 = .{
    -29, -51, -23, -15, -22, -18, -50, -64, -42, -20, -10, -5,  -2,  -20, -23, -44, -23, -3,  -1,  15,
    10,  -3,  -20, -22, -18, -6,  16,  25,  16,  17,  4,   -18, -17, 3,   22,  22,  22,  11,  8,   -18,
    -24, -20, 10,  9,   -1,  -9,  -19, -41, -25, -8,  -25, -2,  -9,  -25, -24, -52, -58, -38, -13, -28,
    -31, -27, -63, -99,
};

const WBISHOP_MID_PST: [64]i16 = .{
    -33, -3, -14, -21, -13, -12, -39, -21, 4,  15,  16,  0,  7,   21,  33,  1,   0,  15,  15, 15, 14, 27, 18,
    10,  -6, 13,  13,  26,  34,  12,  10,  4,  -4,  5,   19, 50,  37,  37,  7,   -2, -16, 37, 43, 40, 35, 50,
    37,  -2, -26, 16,  -18, -13, 30,  59,  18, -47, -29, 4,  -82, -37, -25, -42, 7,  -8,
};

const WBISHOP_END_PST: [64]i16 = .{
    -23, -9,  -23, -5, -9, -16, -5, -17, -14, -18, -7, -1,  4,   -9,  -15, -27, -12, -3, 8,   10,  13, 3,
    -7,  -15, -6,  3,  13, 19,  7,  10,  -3,  -9,  -3, 9,   12,  9,   14,  10,  3,   2,  2,   -8,  0,  -1,
    -2,  6,   0,   4,  -8, -4,  7,  -12, -3,  -13, -4, -14, -14, -21, -11, -8,  -7,  -9, -17, -24,
};

const WROOK_MID_PST: [64]i16 = .{
    -19, -13, 1,   17,  16,  7,  -37, -26, -44, -16, -20, -9,  -1, 11, -6, -71, -45, -25, -16, -17, 3,  0,
    -5,  -33, -36, -26, -12, -1, 9,   -7,  6,   -23, -24, -11, 7,  26, 24, 35,  -8,  -20, -5,  19,  26, 36,
    17,  45,  61,  16,  27,  32, 58,  62,  80,  67,  26,  44,  32, 42, 32, 51,  63,  9,   31,  43,
};

const WROOK_END_PST: [64]i16 = .{
    -9, 2,  3,  -1, -5, -13, 4,  -20, -6, -6, 0,  2,  -9, -9, -11, -3, -4, 0, -5, -1, -7, -12, -8, -16,
    3,  5,  8,  4,  -5, -6,  -8, -11, 4,  3,  13, 1,  2,  1,  -1,  2,  7,  7, 7,  5,  4,  -3,  -5, -3,
    11, 13, 13, 11, -3, 3,   8,  3,   13, 10, 18, 15, 12, 12, 8,   5,
};

const WQUEEN_MID_PST: [64]i16 = .{
    -1, -18, -9,  10,  -15, -25, -31, -50, -35, -8,  11,  2,   8,   15, -3, 1,  -14, 2,   -11, -2, -5, 2,  14,
    5,  -9,  -26, -9,  -10, -2,  -4,  3,   -3,  -27, -27, -16, -16, -1, 17, -2, 1,   -13, -17, 7,  8,  29, 56,
    47, 57,  -24, -39, -5,  1,   -16, 57,  28,  54,  -28, 0,   29,  12, 59, 44, 43,  45,
};

const WQUEEN_END_PST: [64]i16 = .{
    -33, -28, -22, -43, -5,  -32, -20, -41, -22, -23, -30, -16, -16, -23, -36, -32, -16, -27, 15, 6,
    9,   17,  10,  5,   -18, 28,  19,  47,  31,  34,  39,  23,  3,   22,  24,  45,  57,  40,  57, 36,
    -20, 6,   9,   49,  47,  35,  19,  9,   -17, 20,  32,  41,  58,  25,  30,  0,   -9,  22,  22, 27,
    27,  19,  10,  20,
};

const WKING_MID_PST: [64]i16 = .{
    -15, 36,  12,  -54, 8,   -28, 24,  14,  1,   7,   -8,  -64, -43, -16, 9,   8,   -14, -14, -22, -46, -44, -30,
    -15, -27, -49, -1,  -27, -39, -46, -44, -33, -51, -17, -20, -12, -27, -30, -25, -14, -36, -9,  24,  2,   -16,
    -20, 6,   22,  -22, 29,  -1,  -20, -7,  -8,  -4,  -38, -29, -65, 23,  16,  -15, -56, -34, 2,   13,
};

const WKING_END_PST: [64]i16 = .{
    -53, -34, -21, -11, -28, -14, -24, -43, -27, -11, 4,   13, 14, 4,  -5,  -17, -19, -3,  11,  21, 23,
    16,  7,   -9,  -18, -4,  21,  24,  27,  23,  9,   -11, -8, 22, 24, 27,  26,  33,  26,  3,   10, 17,
    23,  15,  20,  45,  44,  13,  -12, 17,  14,  17,  17,  38, 23, 11, -74, -35, -18, -18, -11, 15, 4,
    -17,
};

var BPAWN_MID_PST: [64]i16 = undefined;
var BPAWN_END_PST: [64]i16 = undefined;
var BKNIGHT_MID_PST: [64]i16 = undefined;
var BKNIGHT_END_PST: [64]i16 = undefined;
var BBISHOP_MID_PST: [64]i16 = undefined;
var BBISHOP_END_PST: [64]i16 = undefined;
var BROOK_MID_PST: [64]i16 = undefined;
var BROOK_END_PST: [64]i16 = undefined;
var BQUEEN_MID_PST: [64]i16 = undefined;
var BQUEEN_END_PST: [64]i16 = undefined;
var BKING_MID_PST: [64]i16 = undefined;
var BKING_END_PST: [64]i16 = undefined;

fn flip_pst(src: []const i16, dst: []i16) void {
    var i: usize = 0;
    while (i < 64) : (i += 1) {
        const i_rank = i / 8;
        const i_file = i % 8;
        const idx = (7 - i_rank) * 8 + i_file;
        dst[idx] = -src[i];
    }
}

fn flip_pst_tables() void {
    flip_pst(&WPAWN_MID_PST, &BPAWN_MID_PST);
    flip_pst(&WPAWN_END_PST, &BPAWN_END_PST);
    flip_pst(&WKNIGHT_MID_PST, &BKNIGHT_MID_PST);
    flip_pst(&WKNIGHT_END_PST, &BKNIGHT_END_PST);
    flip_pst(&WBISHOP_MID_PST, &BBISHOP_MID_PST);
    flip_pst(&WBISHOP_END_PST, &BBISHOP_END_PST);
    flip_pst(&WROOK_MID_PST, &BROOK_MID_PST);
    flip_pst(&WROOK_END_PST, &BROOK_END_PST);
    flip_pst(&WQUEEN_MID_PST, &BQUEEN_MID_PST);
    flip_pst(&WQUEEN_END_PST, &BQUEEN_END_PST);
    flip_pst(&WKING_MID_PST, &BKING_MID_PST);
    flip_pst(&WKING_END_PST, &BKING_END_PST);
}
