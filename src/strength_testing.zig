const std = @import("std");
const board = @import("board.zig");
const Board = board.Board;
const Piece = board.Piece;
const Colour = board.Colour;
const MoveType = @import("movegen.zig").MoveType;
const util = @import("util.zig");
const search = @import("search.zig");
const tt = @import("tt.zig");
const UCI = @import("uci.zig").UCI;

pub const std_options = .{ .log_level = std.log.Level.debug };

const EpdMoveType = enum {
    Quiet,
    Cap,
    Kingside,
    Queenside,

    fn eq_movegen(self: EpdMoveType, m: MoveType) bool {
        return switch (self) {
            .Quiet => switch (m) {
                .QUIET, .DOUBLE, .PROMO => true,
                else => false,
            },
            .Cap => switch (m) {
                .CAP, .NPROMOCAP, .RPROMOCAP, .BPROMOCAP, .QPROMOCAP, .EP => true,
                else => false,
            },
            .Kingside => switch (m) {
                .WKINGSIDE, .BKINGSIDE => true,
                else => false,
            },
            .Queenside => switch (m) {
                .WQUEENSIDE, .BQUEENSIDE => true,
                else => false,
            },
        };
    }
};

// when compareing with Move make sure mt is checked first
// only continue if it is correct
const EdpBestMove = struct {
    piece: Piece,
    to: usize,
    mt: EpdMoveType,
};

const EPD = struct { id: []const u8, pos: Board, bms: []const EdpBestMove };

fn map_edp_piece(p: u8) ?Piece {
    return switch (p) {
        'N' => Piece.KNIGHT,
        'R' => Piece.ROOK,
        'B' => Piece.BISHOP,
        'Q' => Piece.QUEEN,
        'K' => Piece.KING,
        else => null,
    };
}

fn parse_bm(bm_str: []const u8, ctm: Colour) !EdpBestMove {
    if (bm_str.len < 2) return error.InvalidBM;

    if (std.mem.eql(u8, bm_str, "O-O")) {
        return EdpBestMove{
            .mt = EpdMoveType.Kingside,
            .piece = undefined,
            .to = undefined,
        };
    }

    if (std.mem.eql(u8, bm_str, "O-O-O")) {
        return EdpBestMove{
            .mt = EpdMoveType.Queenside,
            .piece = undefined,
            .to = undefined,
        };
    }

    const trimmed = std.mem.trim(u8, bm_str, "+#");
    const piece = (map_edp_piece(trimmed[0]) orelse Piece.PAWN).with_ctm(ctm);
    const to = try util.sq_from_str(trimmed[trimmed.len - 2 .. trimmed.len]);
    const mt = if (std.mem.indexOfScalar(u8, trimmed, 'x')) |_| EpdMoveType.Cap else EpdMoveType.Quiet;

    // TODO BK and WAC moves both don't have promotions, but might be something to handle later

    return EdpBestMove{ .piece = piece, .to = to, .mt = mt };
}

// the returned EPD owns all of its memory
// feel free to deallocate it once you are done with this
fn parse_epd(allocator: std.mem.Allocator, str: []const u8) !EPD {
    var fen_bm_it = std.mem.splitSequence(u8, str, " bm ");
    const fen = fen_bm_it.next() orelse return error.InvalidEDP;
    const b = try board.board_from_fen(fen);

    const bm_id_str = fen_bm_it.next() orelse return error.InvalidEDP;
    var bm_id_it = std.mem.splitScalar(u8, bm_id_str, ';');
    const bm_str = bm_id_it.next() orelse return error.InvalidEDP;

    var bms = std.ArrayList(EdpBestMove).init(allocator);
    var bm_it = std.mem.splitScalar(u8, bm_str, ' ');
    while (bm_it.next()) |s| {
        try bms.append(try parse_bm(s, b.ctm));
    }

    const id_str = bm_id_it.next() orelse return error.InvalidEDP;
    var id_it = std.mem.splitScalar(u8, id_str, '"');
    // discard the first 'id "'
    _ = id_it.next() orelse return error.InvalidEDP;
    const id = id_it.next() orelse return error.InvalidEDP;

    return EPD{
        .id = try allocator.dupe(u8, id),
        .pos = b,
        .bms = try bms.toOwnedSlice(),
    };
}

fn epd_search(epd: EPD) !bool {
    std.log.debug("====== trying {s} ======", .{epd.id});
    epd.pos.log(std.log.debug);
    for (epd.bms) |bm| {
        var buf: [4]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        try util.write_sq(fbs.writer(), bm.to);
        std.log.debug("--- expected move {s} {s} ({d}) {s} ---", .{
            @tagName(bm.piece),
            fbs.getWritten(),
            bm.to,
            @tagName(bm.mt),
        });
    }

    var uci = UCI{ .board = epd.pos, .log_file = null };

    const res = search.do_search(&uci, &epd.pos) catch {
        std.log.debug("{s} position failed low!", .{epd.id});
        return false;
    };

    var found_bm = false;
    for (epd.bms) |bm| {
        var matches = true;
        if (res.move.piece != bm.piece) matches = false;
        if (res.move.to != bm.to) matches = false;
        if (!bm.mt.eq_movegen(res.move.mt)) matches = false;

        if (matches) found_bm = true;
    }

    std.log.debug("got: score = {d}", .{res.score});
    res.move.log(std.log.debug);

    return found_bm;
}

fn usage_and_die() noreturn {
    const usage =
        \\Usage is either:
        \\zig build st -- <file.epd> [start test num] [end test num]
        \\	or
        \\zig build st -- pos '<epd line>'
    ;

    std.log.err("{s}", .{usage});
    std.process.exit(1);
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args = try std.process.argsWithAllocator(allocator);

    _ = args.next();

    const filename = args.next() orelse usage_and_die();

    if (std.mem.eql(u8, filename, "pos")) {
        const epd = try parse_epd(allocator, args.next() orelse usage_and_die());
        const passed = try epd_search(epd);
        std.log.info("{s} {s}", .{ epd.id, if (passed) "passed" else "failed" });
        return;
    }

    const start: usize = if (args.next()) |a| try std.fmt.parseInt(usize, a, 10) else 0;
    const end: ?usize = if (args.next()) |a| try std.fmt.parseInt(usize, a, 10) else null;

    std.log.debug("start {d} end {?d}", .{ start, end });

    const file = try std.fs.cwd().openFile(filename, .{});
    const reader = file.reader();

    var count: usize = 0;
    var passed_count: usize = 0;
    var failed_count: usize = 0;

    var buf: [1024]u8 = undefined;
    while (try reader.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        if (count < start) {
            count += 1;
            continue;
        }
        if (end) |e| if (count > e) break;

        const epd = try parse_epd(allocator, line);
        const passed = try epd_search(epd);
        if (passed) passed_count += 1 else failed_count += 1;
        std.log.info("{s} {s}", .{ epd.id, if (passed) "passed" else "failed" });

        tt.clear();
        count += 1;
    }

    const total: usize = passed_count + failed_count;
    const percentage: f64 = @as(f64, @floatFromInt(passed_count)) / @as(f64, @floatFromInt(total)) * 100;
    std.log.info("passed {}, failed {}, total {} ({d:.2}%)", .{ passed_count, failed_count, total, percentage });
}
