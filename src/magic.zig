const std = @import("std");
const log = std.log;

const board = @import("board.zig");
const BB = board.BB;
const util = @import("util.zig");
const log_bb = util.log_bb;

const c = @cImport(@cInclude("magic.h"));

var bishop_move_table: [64][512]BB = undefined;
var rook_move_table: [64][4096]BB = undefined;

const SquareMagic = struct { magic: u64, mask: BB };

// magics generated previously from rook and roll
const rook_magics: [64]SquareMagic = [_]SquareMagic{ .{ .magic = 0x40800022400A1080, .mask = 0x101010101017e }, .{ .magic = 0x420401001E800, .mask = 0x202020202027c }, .{ .magic = 0x100402000110005, .mask = 0x404040404047a }, .{ .magic = 0x4288002010500008, .mask = 0x8080808080876 }, .{ .magic = 0x60400200040001C0, .mask = 0x1010101010106e }, .{ .magic = 0x50001000208C400, .mask = 0x2020202020205e }, .{ .magic = 0x1008240803000840, .mask = 0x4040404040403e }, .{ .magic = 0x2000044018A2201, .mask = 0x8080808080807e }, .{ .magic = 0x70401040042000, .mask = 0x1010101017e00 }, .{ .magic = 0x2882030131020803, .mask = 0x2020202027c00 }, .{ .magic = 0x4A00100850800, .mask = 0x4040404047a00 }, .{ .magic = 0x205400400400840, .mask = 0x8080808087600 }, .{ .magic = 0x3012000401100620, .mask = 0x10101010106e00 }, .{ .magic = 0x80104200008404, .mask = 0x20202020205e00 }, .{ .magic = 0x148325380100, .mask = 0x40404040403e00 }, .{ .magic = 0x8000120222408100, .mask = 0x80808080807e00 }, .{ .magic = 0x8484821011400400, .mask = 0x10101017e0100 }, .{ .magic = 0x8204044020203000, .mask = 0x20202027c0200 }, .{ .magic = 0x88020300A0010004, .mask = 0x40404047a0400 }, .{ .magic = 0x4120200102024280, .mask = 0x8080808760800 }, .{ .magic = 0x100200092408044C, .mask = 0x101010106e1000 }, .{ .magic = 0x80208014010000C0, .mask = 0x202020205e2000 }, .{ .magic = 0x1000820820040, .mask = 0x404040403e4000 }, .{ .magic = 0x10600A000401100, .mask = 0x808080807e8000 }, .{ .magic = 0x4824080013020, .mask = 0x101017e010100 }, .{ .magic = 0x8010200008844040, .mask = 0x202027c020200 }, .{ .magic = 0x41000424044040, .mask = 0x404047a040400 }, .{ .magic = 0x1C08008012400220, .mask = 0x8080876080800 }, .{ .magic = 0x2200200041200, .mask = 0x1010106e101000 }, .{ .magic = 0x1040049088460400, .mask = 0x2020205e202000 }, .{ .magic = 0x218C4800412A0, .mask = 0x4040403e404000 }, .{ .magic = 0x2009A008004080, .mask = 0x8080807e808000 }, .{ .magic = 0x80010200A40808, .mask = 0x1017e01010100 }, .{ .magic = 0x2010004801200092, .mask = 0x2027c02020200 }, .{ .magic = 0x220B02004040005, .mask = 0x4047a04040400 }, .{ .magic = 0xC00080080801000, .mask = 0x8087608080800 }, .{ .magic = 0x3002110400080044, .mask = 0x10106e10101000 }, .{ .magic = 0x40002021110C2, .mask = 0x20205e20202000 }, .{ .magic = 0x2010081042009104, .mask = 0x40403e40404000 }, .{ .magic = 0x460802000480104, .mask = 0x80807e80808000 }, .{ .magic = 0x5441020100202800, .mask = 0x17e0101010100 }, .{ .magic = 0x800810221160400, .mask = 0x27c0202020200 }, .{ .magic = 0x1084200E0008, .mask = 0x47a0404040400 }, .{ .magic = 0x10281003010002, .mask = 0x8760808080800 }, .{ .magic = 0x2204004081000800, .mask = 0x106e1010101000 }, .{ .magic = 0x1803204140100400, .mask = 0x205e2020202000 }, .{ .magic = 0x840B002110024, .mask = 0x403e4040404000 }, .{ .magic = 0x201805082220001, .mask = 0x807e8080808000 }, .{ .magic = 0x7324118001006208, .mask = 0x7e010101010100 }, .{ .magic = 0x1012402001830004, .mask = 0x7c020202020200 }, .{ .magic = 0x100E000806002020, .mask = 0x7a040404040400 }, .{ .magic = 0xA0201408020200, .mask = 0x76080808080800 }, .{ .magic = 0x110100802110018, .mask = 0x6e101010101000 }, .{ .magic = 0x30001800080, .mask = 0x5e202020202000 }, .{ .magic = 0x2280005200911080, .mask = 0x3e404040404000 }, .{ .magic = 0x101024220108008, .mask = 0x7e808080808000 }, .{ .magic = 0x2000800100402011, .mask = 0x7e01010101010100 }, .{ .magic = 0x11020080400A, .mask = 0x7c02020202020200 }, .{ .magic = 0x200200044184111A, .mask = 0x7a04040404040400 }, .{ .magic = 0x68900A0004121036, .mask = 0x7608080808080800 }, .{ .magic = 0x600900100380083, .mask = 0x6e10101010101000 }, .{ .magic = 0x8001000400020481, .mask = 0x5e20202020202000 }, .{ .magic = 0x60068802491402, .mask = 0x3e40404040404000 }, .{ .magic = 0x8000010038804402, .mask = 0x7e80808080808000 } };

const bishop_magics: [64]SquareMagic = [_]SquareMagic{
    .{ .magic = 0x2140004101030008, .mask = 0x40201008040200 },
    .{ .magic = 0xA30208100100420, .mask = 0x402010080400 },
    .{ .magic = 0x102028202000101, .mask = 0x4020100A00 },
    .{ .magic = 0x141104008002500, .mask = 0x40221400 },
    .{ .magic = 0x6008142001A8002A, .mask = 0x2442800 },
    .{ .magic = 0x81402400A8300, .mask = 0x204085000 },
    .{ .magic = 0x20904410420020, .mask = 0x20408102000 },
    .{ .magic = 0x8048108804202010, .mask = 0x2040810204000 },
    .{ .magic = 0x8001480520440080, .mask = 0x20100804020000 },
    .{ .magic = 0x108920168001080, .mask = 0x40201008040000 },
    .{ .magic = 0x10821401002208, .mask = 0x4020100A0000 },
    .{ .magic = 0x9004100D000, .mask = 0x4022140000 },
    .{ .magic = 0x80A00444804C6010, .mask = 0x244280000 },
    .{ .magic = 0x8004020200240001, .mask = 0x20408500000 },
    .{ .magic = 0x10000882002A0A48, .mask = 0x2040810200000 },
    .{ .magic = 0x2000100220681412, .mask = 0x4081020400000 },
    .{ .magic = 0x2240800700410, .mask = 0x10080402000200 },
    .{ .magic = 0x38080020401082, .mask = 0x20100804000400 },
    .{ .magic = 0x12C0920100410100, .mask = 0x4020100A000A00 },
    .{ .magic = 0x220100404288000, .mask = 0x402214001400 },
    .{ .magic = 0x24009A00850000, .mask = 0x24428002800 },
    .{ .magic = 0x2422000040100180, .mask = 0x2040850005000 },
    .{ .magic = 0x322C010022820040, .mask = 0x4081020002000 },
    .{ .magic = 0x89040C010040, .mask = 0x8102040004000 },
    .{ .magic = 0x400602001022230, .mask = 0x8040200020400 },
    .{ .magic = 0x401008000128006C, .mask = 0x10080400040800 },
    .{ .magic = 0x421004420080, .mask = 0x20100A000A1000 },
    .{ .magic = 0xA420202008008020, .mask = 0x40221400142200 },
    .{ .magic = 0x1010120104000, .mask = 0x2442800284400 },
    .{ .magic = 0x8881480000882C0, .mask = 0x4085000500800 },
    .{ .magic = 0x860112C112104108, .mask = 0x8102000201000 },
    .{ .magic = 0x10A1082042000420, .mask = 0x10204000402000 },
    .{ .magic = 0x100248104100684, .mask = 0x4020002040800 },
    .{ .magic = 0x214188200A00640, .mask = 0x8040004081000 },
    .{ .magic = 0x4881008210820, .mask = 0x100A000A102000 },
    .{ .magic = 0x2000280800020A00, .mask = 0x22140014224000 },
    .{ .magic = 0x40008201610104, .mask = 0x44280028440200 },
    .{ .magic = 0x2004093020001220, .mask = 0x8500050080400 },
    .{ .magic = 0x81004501000800C, .mask = 0x10200020100800 },
    .{ .magic = 0x234841900C081016, .mask = 0x20400040201000 },
    .{ .magic = 0x704009221000402, .mask = 0x2000204081000 },
    .{ .magic = 0x4540380010000214, .mask = 0x4000408102000 },
    .{ .magic = 0x2030082000040, .mask = 0xA000A10204000 },
    .{ .magic = 0x8050808104093, .mask = 0x14001422400000 },
    .{ .magic = 0x101188107464808, .mask = 0x28002844020000 },
    .{ .magic = 0x5041020802400802, .mask = 0x50005008040200 },
    .{ .magic = 0x4010B44808850040, .mask = 0x20002010080400 },
    .{ .magic = 0x10100040088000E0, .mask = 0x40004020100800 },
    .{ .magic = 0x84C010108010, .mask = 0x20408102000 },
    .{ .magic = 0x800488140100, .mask = 0x40810204000 },
    .{ .magic = 0x1000028020218440, .mask = 0xA1020400000 },
    .{ .magic = 0x5010048A06220000, .mask = 0x142240000000 },
    .{ .magic = 0x8001040812041000, .mask = 0x284402000000 },
    .{ .magic = 0x1840026008109400, .mask = 0x500804020000 },
    .{ .magic = 0x1046002206001882, .mask = 0x201008040200 },
    .{ .magic = 0x20204400D84000, .mask = 0x402010080400 },
    .{ .magic = 0x1270C20060804000, .mask = 0x2040810204000 },
    .{ .magic = 0x2000021113042200, .mask = 0x4081020400000 },
    .{ .magic = 0x40002412282008A, .mask = 0xA102040000000 },
    .{ .magic = 0xC000000041100, .mask = 0x14224000000000 },
    .{ .magic = 0x1000200060005104, .mask = 0x28440200000000 },
    .{ .magic = 0x1840042164280880, .mask = 0x50080402000000 },
    .{ .magic = 0x964AD0002100AA00, .mask = 0x20100804020000 },
    .{ .magic = 0x2190900041002410, .mask = 0x40201008040200 },
};

fn un_shl(shift: anytype) usize {
    return @as(usize, 1) << @as(u6, @intCast(shift));
}

// code to generate magics from
// https://www.chessprogramming.org/Looking_for_Magics

const bit_table: [64]usize = [_]usize{ 63, 30, 3, 32, 25, 41, 22, 33, 15, 50, 42, 13, 11, 53, 19, 34, 61, 29, 2, 51, 21, 43, 45, 10, 18, 47, 1, 54, 9, 57, 0, 35, 62, 31, 40, 4, 49, 5, 52, 26, 60, 6, 23, 44, 46, 27, 56, 16, 7, 39, 48, 24, 59, 14, 12, 55, 38, 28, 58, 20, 37, 17, 36, 8 };

fn pop_1st_bit(bb: *u64) usize {
    const b: u64 = bb.* ^ (bb.* - 1);
    const fold: u32 = @intCast((b & 0xffffffff) ^ (b >> 32));
    bb.* &= (bb.* - 1);
    return bit_table[@mulWithOverflow(fold, 0x783a9b23).@"0" >> 26];
}

fn index_to_u64(index: usize, bits: usize, m: u64) u64 {
    var mask = m;
    var result: u64 = 0;
    for (0..bits) |i| {
        const j = pop_1st_bit(&mask);
        if (index & un_shl(i) > 0) {
            result |= un_shl(j);
        }
    }

    return result;
}

fn rmask(sq: i32) u64 {
    var result: u64 = 0;
    const rk = sq / 8;
    const fl = sq % 8;

    var r = rk + 1;
    while (r <= 6) : (r += 1) {
        result |= 1 << (fl + r * 8);
    }

    r = if (rk == 0) 0 else rk - 1;
    while (r >= 1) : (r -= 1) {
        result |= un_shl(fl + r * 8);
    }

    var f = fl + 1;
    while (f <= 6) : (f += 1) {
        result |= (un_shl(f + rk * 8));
    }

    f = if (fl == 0) 0 else fl - 1;
    while (f >= 1) : (f -= 1) {
        result |= (un_shl(f + rk * 8));
    }

    return result;
}

fn bmask(sq: i32) u64 {
    var result: u64 = 0;
    const rk = sq / 8;
    const fl = sq % 8;

    var r = rk + 1;
    var f = fl + 1;
    while (r <= 6 and f <= 6) : ({
        r += 1;
        f += 1;
    }) {
        result |= (un_shl(f + r * 8));
    }

    r = rk + 1;
    f = fl - 1;
    while (r <= 6 and f >= 1) : ({
        r += 1;
        f -= 1;
    }) {
        result |= (un_shl(f + r * 8));
    }

    r = rk - 1;
    f = fl + 1;
    while (r >= 1 and f <= 6) : ({
        r -= 1;
        f += 1;
    }) {
        result |= (un_shl(f + r * 8));
    }

    r = rk - 1;
    f = fl - 1;
    while (r >= 1 and f >= 1) : ({
        r -= 1;
        f -= 1;
    }) {
        result |= (un_shl(f + r * 8));
    }

    return result;
}

fn ratt(sq: usize, block: BB) u64 {
    var result: u64 = 0;
    const rk: i32 = @intCast(sq / 8);
    const fl: i32 = @intCast(sq % 8);

    var r: i32 = rk + 1;
    while (r <= 7) : (r += 1) {
        result |= un_shl(fl + r * 8);
        if ((block & un_shl(fl + r * 8)) > 0) {
            break;
        }
    }

    if (rk > 0) {
        r = rk - 1;
        while (r >= 0) : (r -= 1) {
            result |= un_shl(fl + r * 8);
            if ((block & un_shl(fl + r * 8)) > 0) {
                break;
            }
        }
    }

    var f: i32 = fl + 1;
    while (f <= 7) : (f += 1) {
        result |= (un_shl(f + rk * 8));
        if ((block & un_shl(f + rk * 8)) > 0) {
            break;
        }
    }

    if (fl > 0) {
        f = fl - 1;
        while (f >= 0) : (f -= 1) {
            result |= (un_shl(f + rk * 8));
            if ((block & un_shl(f + rk * 8)) > 0) {
                break;
            }
        }
    }

    return result;
}

fn batt(sq: usize, block: BB) u64 {
    var result: u64 = 0;
    const rk = sq / 8;
    const fl = sq % 8;

    var r = rk + 1;
    var f = fl + 1;
    while (r <= 6 and f <= 6) : ({
        r += 1;
        f += 1;
    }) {
        result |= (un_shl(f + r * 8));
        if (block & (un_shl(f + r * 8)) > 0) {
            break;
        }
    }

    r = rk + 1;
    f = if (fl < 1) 0 else fl - 1;
    while (r <= 6 and f >= 1) : ({
        r += 1;
        f -= 1;
    }) {
        result |= (un_shl(f + r * 8));
        if (block & (un_shl(f + r * 8)) > 0) {
            break;
        }
    }

    r = if (rk < 1) 0 else rk - 1;
    f = fl + 1;
    while (r >= 1 and f <= 6) : ({
        r -= 1;
        f += 1;
    }) {
        result |= (un_shl(f + r * 8));
        if (block & (un_shl(f + r * 8)) > 0) {
            break;
        }
    }

    r = if (rk < 1) 0 else rk - 1;
    f = if (fl < 1) 0 else fl - 1;
    while (r >= 1 and f >= 1) : ({
        r -= 1;
        f -= 1;
    }) {
        result |= (un_shl(f + r * 8));
        if (block & (un_shl(f + r * 8)) > 0) {
            break;
        }
    }

    return result;
}

fn transform(b: u64, magic: u64, bits: comptime_int) usize {
    const mul: u64 = @mulWithOverflow(b, magic).@"0";
    const idx: i32 = @intCast(mul >> (64 - bits));
    return @intCast(idx);
}

fn populate_move_table(move_table: []BB, comptime m: SquareMagic, comptime sq: comptime_int, comptime shift: comptime_int, comptime is_bishop: bool) void {
    var occs: [4096]BB = undefined;
    var atts: [4096]BB = undefined;

    const bits: u6 = @intCast(@popCount(m.mask));
    const bshft = un_shl(bits);
    for (0..bshft) |i| {
        occs[i] = index_to_u64(i, bits, m.mask);
        atts[i] = if (is_bishop) batt(sq, occs[i]) else ratt(sq, occs[i]);

        if (!is_bishop and sq == 3) {
            log.debug("occ, for for bshift: {d}", .{i});
            log_bb(occs[i], log.debug);
            log_bb(atts[i], log.debug);
        }
    }

    for (0..bshft) |i| {
        move_table[i] = 0;
    }

    for (0..bshft) |i| {
        const idx = transform(occs[i], m.magic, shift);
        if (!is_bishop and sq == 3 and idx == 469) {
            log.debug("idx for occ {d} = {d}", .{ i, idx });
            log_bb(occs[i], log.debug);
            log_bb(atts[i], log.debug);
        }
        move_table[idx] = atts[i];
    }
}

const BISHOP_SHIFT = 9;
const ROOK_SHIFT = 9;

pub fn init_magics() void {
    inline for (0..64) |sq| {
        populate_move_table(&rook_move_table[sq], rook_magics[sq], sq, ROOK_SHIFT, false);
        populate_move_table(&bishop_move_table[sq], bishop_magics[sq], sq, BISHOP_SHIFT, true);
    }

    // inline for (0..64) |sq| {
    //     const r_mag = c.SquareMagic{
    //         .magic = rook_magics[sq].magic,
    //         .mask = rook_magics[sq].mask,
    //     };
    //     c.populate_move_table(&rook_move_table[sq], r_mag, sq, ROOK_SHIFT, false);
    //     const b_mag = c.SquareMagic{
    //         .magic = bishop_magics[sq].magic,
    //         .mask = bishop_magics[sq].mask,
    //     };
    //     c.populate_move_table(&bishop_move_table[sq], b_mag, sq, BISHOP_SHIFT, true);
    // }

    log.debug("sq 3 idx 469 is:", .{});
    log_bb(rook_move_table[3][469], log.debug);
}

pub fn lookup_bishop(occ: BB, sq: usize) BB {
    var o = occ;
    o &= bishop_magics[sq].mask;
    o = @mulWithOverflow(o, bishop_magics[sq].magic).@"0";
    o >>= 64 - BISHOP_SHIFT;
    return bishop_move_table[sq][o];
}

pub fn lookup_bishop_xray(occ: BB, blockers: BB, sq: usize) BB {
    var blk = blockers;
    const atts = lookup_bishop(occ, sq);
    blk &= atts;
    return atts ^ lookup_bishop(occ ^ blk, sq);
}

pub fn lookup_rook(occ: BB, sq: usize) BB {
    // var o = occ;
    const o = occ & rook_magics[sq].mask;
    const idx = transform(o, rook_magics[sq].magic, ROOK_SHIFT);
    // o &= rook_magics[sq].mask;
    // o = @mulWithOverflow(o, rook_magics[sq].magic).@"0";
    // o >>= 64 - ROOK_SHIFT;

    const moves = rook_move_table[sq][idx];
    if (sq == 3 or sq == 7) {
        log.debug("lookup_rook occ, mask, occmask, moves: ", .{});
        util.log_bb(occ, log.debug);
        util.log_bb(rook_magics[sq].mask, log.debug);
        util.log_bb(o, log.debug);
        util.log_bb(moves, log.debug);
    }

    return moves;
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
