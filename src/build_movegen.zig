const std = @import("std");

const board = @import("board.zig");
const BB = board.BB;
const square = board.square;
const File = board.File;
const Rank = board.Rank;

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

fn write_bb_array(w: anytype, a: []BB, name: []const u8) !void {
    try std.fmt.format(w, "pub const {s}: [{d}]BB = .{{\n", .{ name, a.len });
    for (a) |bb| {
        try std.fmt.format(w, "\t0x{X},\n", .{bb});
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

    try write_bb_array(w, &pawn_attack_table, "pawn_attack_table");
    try write_bb_array(w, &knight_move_table, "knight_move_table");
    try write_bb_array(w, &king_move_table, "king_move_table");
    try write_bb_array(w, &super_moves, "super_moves");

    try write_sq_mag(w, &rook_magics, "rook_magics");
    try write_sq_mag(w, &bishop_magics, "bishop_magics");

    try write_mt_array(w, 4096, &rook_move_table, "rook_move_table");
    try write_mt_array(w, 512, &bishop_move_table, "bishop_move_table");

    return std.process.cleanExit();
}

// the following is heavily inspired by https://www.chessprogramming.org/Looking_for_Magics

// const RANDOM_SEED: u64 = 7252092290257123456;
const RANDOM_SEED: u64 = 9379609607221297880;

const MAGIC_ITERS: usize = 1000000000;

var rng = std.Random.DefaultPrng.init(RANDOM_SEED);
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
    // const rmags = @constCast(&rook_magics);
    // const rmoves = @constCast(&rook_move_table);

    // const bmags = @constCast(&bishop_magics);
    // const bmoves = @constCast(&bishop_move_table);
    // inline for (0..64) |sq| {
    //     rmags[sq] = try gen_magic(&rmoves[sq], sq, RSHIFT, true);
    //     bmags[sq] = try gen_magic(&bmoves[sq], sq, BSHIFT, false);
    // }

    inline for (0..64) |sq| {
        rook_magics[sq] = try gen_magic(&rook_move_table[sq], sq, RSHIFT, true);
        bishop_magics[sq] = try gen_magic(&bishop_move_table[sq], sq, BSHIFT, false);
    }
}
