const std = @import("std");
const board = @import("board.zig");
const Board = board.Board;
const Move = @import("movegen.zig").Move;
const algebraic_to_move = @import("pgn.zig").algebraic_to_move;

pub const std_options: std.Options = .{
    .log_level = .debug,
};

// const c = @cImport({
//     @cInclude("sqlite3");
// });

const ELO_THRES = 1000;

fn parse_elo(elo_line: []const u8) !usize {
    var it = std.mem.splitScalar(u8, elo_line, '"');

    // discard before the first quote
    _ = it.next() orelse return error.FailedParsingElo;

    const elo_str = it.next() orelse return error.FailedParsingElo;
    return std.fmt.parseInt(usize, elo_str, 10);
}

fn looks_like_move(str: []const u8) bool {
    if (str.len == 0) return false;
    return switch (str[0]) {
        'a'...'h' => true, // if file for pawn move
        'N', 'R', 'B', 'Q', 'K' => true,
        else => false,
    };
}

fn strip_move_annotations(move: []const u8) []const u8 {
    var end = move.len;
    while (end > 1 and (move[end - 1] == '?' or move[end - 1] == '!')) {
        end -= 1;
    }

    return move[0..end];
}

fn parse_pgn_moves(allocator: std.mem.Allocator, str: []const u8) ![]Move {
    var moves = try std.ArrayList(Move).initCapacity(allocator, 10);
    var b = board.default_board();
    var next: Board = undefined;

    var it = std.mem.splitScalar(u8, str, ' ');
    while (it.next()) |s| {
        if (!looks_like_move(s)) continue;

        const move_str = strip_move_annotations(s);
        const m = try algebraic_to_move(&b, move_str);
        b.copy_make(&next, m);
        b = next;

        try moves.append(allocator, m);
    }

    return moves.items;
}

const PGN = struct {
    white_elo: usize,
    black_elo: usize,
    moves: []Move,

    fn initFromStr(allocator: std.mem.Allocator, str: []const u8) !PGN {
        std.log.debug("init from str: {s}", .{str});
        var white_elo: ?usize = null;
        var black_elo: ?usize = null;
        var moves: ?[]Move = null;

        var reader = std.Io.Reader.fixed(str);

        while (reader.takeDelimiterExclusive('\n')) |line| {
            std.log.debug("line: {s}", .{line});
            if (std.mem.eql(u8, "[WhiteElo", line[0..9])) {
                white_elo = try parse_elo(line);
                if (white_elo orelse 0 < ELO_THRES) return error.EloTooLow;
            }
            if (std.mem.eql(u8, "[BlackElo", line[0..9])) {
                black_elo = try parse_elo(line);
                if (black_elo orelse 0 < ELO_THRES) return error.EloTooLow;
            }

            if (std.mem.eql(u8, "1.", line[0..2])) {
                moves = try parse_pgn_moves(allocator, line);
            }
        } else |err| switch (err) {
            error.EndOfStream, error.StreamTooLong => {},
            else => return err,
        }

        return PGN{
            .white_elo = white_elo orelse return error.UnknownElo,
            .black_elo = black_elo orelse return error.UnknownElo,
            .moves = moves orelse return error.UnknownMoves,
        };
    }

    fn meets_elo_thres(self: PGN, thres: usize) bool {
        return self.white_elo >= thres and self.black_elo >= thres;
    }

    fn deinit(self: PGN, allocator: std.mem.Allocator) void {
        allocator.free(self.moves);
    }
};

const PgnReader = struct {
    reader: *std.Io.Reader,
    buf: std.ArrayList(u8),

    fn init(allocator: std.mem.Allocator, reader: *std.Io.Reader) !*PgnReader {
        const parser = try allocator.create(PgnReader);
        parser.* = .{
            .reader = reader,
            .buf = try std.ArrayList(u8).initCapacity(allocator, 4096),
        };

        return parser;
    }

    fn deinit(self: *PgnReader, allocator: std.mem.Allocator) void {
        self.buf.deinit(allocator);
        allocator.destroy(self);
    }

    // retruns an owned slice to the next pgn
    fn read_pgn(self: *PgnReader, allocator: std.mem.Allocator) ![]const u8 {
        // self.reader.

        defer self.buf.clearRetainingCapacity();

        while (self.reader.takeDelimiterInclusive('\n')) |line| {
            if (line.len == 1 and line[0] == '\n') break; // done parsing tags

            if (line[0] != '[') {
                std.log.err("unexpected line, wanted tag, got '{s}'", .{line});
                return error.PgnExpectedTag;
            }
            try self.buf.appendSlice(allocator, line);
        } else |err| switch (err) {
            error.EndOfStream, error.StreamTooLong => {},
            else => return err,
        }

        try self.buf.appendSlice(allocator, try self.reader.takeDelimiterExclusive('\n'));
        // read the blank line after moves if it is there
        _ = self.reader.takeDelimiterExclusive('\n') catch |err| {
            if (err != error.EndOfStream) return err;
        };

        return allocator.dupe(u8, self.buf.items);
    }
};

const SAMPLE_PGN =
    \\[Event "Rated Bullet tournament https://lichess.org/tournament/yc1WW2Ox"]
    \\[Site "https://lichess.org/PpwPOZMq"]
    \\[Date "2017.04.01"]
    \\[Round "-"]
    \\[White "Abbot"]
    \\[Black "Costello"]
    \\[Result "0-1"]
    \\[UTCDate "2017.04.01"]
    \\[UTCTime "11:32:01"]
    \\[WhiteElo "2100"]
    \\[BlackElo "2000"]
    \\[WhiteRatingDiff "-4"]
    \\[BlackRatingDiff "+1"]
    \\[WhiteTitle "FM"]
    \\[ECO "B30"]
    \\[Opening "Sicilian Defense: Old Sicilian"]
    \\[TimeControl "300+0"]
    \\[Termination "Time forfeit"]
    \\
    \\1. e4 { [%eval 0.17] [%clk 0:00:30] } 1... c5 { [%eval 0.19] [%clk 0:00:30] } 2. Nf3 { [%eval 0.25] [%clk 0:00:29] } 2... Nc6 { [%eval 0.33] [%clk 0:00:30] } 3. Bc4 { [%eval -0.13] [%clk 0:00:28] } 3... e6 { [%eval -0.04] [%clk 0:00:30] } 4. c3 { [%eval -0.4] [%clk 0:00:27] } 4... b5? { [%eval 1.18] [%clk 0:00:30] } 5. Bb3?! { [%eval 0.21] [%clk 0:00:26] } 5... c4 { [%eval 0.32] [%clk 0:00:29] } 6. Bc2 { [%eval 0.2] [%clk 0:00:25] } 6... a5 { [%eval 0.6] [%clk 0:00:29] } 7. d4 { [%eval 0.29] [%clk 0:00:23] } 7... cxd3 { [%eval 0.6] [%clk 0:00:27] } 8. Qxd3 { [%eval 0.12] [%clk 0:00:22] } 8... Nf6 { [%eval 0.52] [%clk 0:00:26] } 9. e5 { [%eval 0.39] [%clk 0:00:21] } 9... Nd5 { [%eval 0.45] [%clk 0:00:25] } 10. Bg5?! { [%eval -0.44] [%clk 0:00:18] } 10... Qc7 { [%eval -0.12] [%clk 0:00:23] } 11. Nbd2?? { [%eval -3.15] [%clk 0:00:14] } 11... h6 { [%eval -2.99] [%clk 0:00:23] } 12. Bh4 { [%eval -3.0] [%clk 0:00:11] } 12... Ba6? { [%eval -0.12] [%clk 0:00:23] } 13. b3?? { [%eval -4.14] [%clk 0:00:02] } 13... Nf4? { [%eval -2.73] [%clk 0:00:21] } 0-1 
;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();

    var reader = std.Io.Reader.fixed(SAMPLE_PGN);
    var pgn_reader = try PgnReader.init(allocator, &reader);
    defer pgn_reader.deinit(allocator);

    const str = try pgn_reader.read_pgn(allocator);
    defer allocator.free(str);

    const pgn = try PGN.initFromStr(allocator, str);
    defer pgn.deinit(allocator);

    for (pgn.moves) |m| {
        var buf: [100]u8 = undefined;
        var fixed = std.Io.Writer.fixed(&buf);
        try m.as_uci_str(&fixed);
        std.log.info("{s}", .{fixed.buffered()});
    }
}
