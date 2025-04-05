const std = @import("std");
const log = std.log;

const board = @import("board.zig");
const BB = board.BB;
const square = board.square;
const util = @import("util.zig");

const SquareMagic = struct { mask: BB, magic: u64 };

var rook_magics: [64]SquareMagic = undefined;
var bishop_magics: [64]SquareMagic = undefined;

var bishop_move_table: [64][512]BB = undefined;
var rook_move_table: [64][4096]BB = undefined;

const RSHIFT = 12; // !
const BSHIFT = 9;

// the following is heavily inspired by https://www.chessprogramming.org/Looking_for_Magics

const RANDOM_SEED: u64 = 7252092290257123456;

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
    inline for (0..64) |sq| {
        rook_magics[sq] = try gen_magic(&rook_move_table[sq], sq, RSHIFT, true);
        bishop_magics[sq] = try gen_magic(&bishop_move_table[sq], sq, BSHIFT, false);
    }
}

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
