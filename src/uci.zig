const std = @import("std");
const File = std.fs.File;
const board = @import("board.zig");
const Board = board.Board;
const tt = @import("tt.zig");
const PV = tt.PV;
const search = @import("search.zig");
const movegen = @import("movegen.zig");
const Move = movegen.Move;
const eval = @import("eval.zig");
const Timer = @import("timer.zig").Timer;

const BOT_NAME = "crig";
const AUTHOR = "George Bull";

const UciCommand = enum(usize) {
    uci,
    //TODO debug
    isready,
    //TODO setoption
    ucinewgame,
    position,
    go,
    //TODO stop
    //TODO ponderhit
    quit,
};

pub const UCI = struct {
    board: Board,
    last_best_move: ?Move,
    writer: *std.Io.Writer,

    pub fn init(
        allocator: std.mem.Allocator,
        writer: *std.Io.Writer,
        b: Board,
    ) !*UCI {
        const uci = try allocator.create(UCI);
        uci.* = .{
            .board = b,
            .last_best_move = null,
            .writer = writer,
        };

        return uci;
    }

    pub fn deinit(self: *UCI, allocator: std.mem.Allocator) void {
        allocator.destroy(self);
    }

    // fn write(self: *UCI, bytes: []const u8) !usize {
    //     try self.stdout_writer.writeAll(bytes);
    //     if (self.log_file) |file| {
    //         _ = try file.writeAll(bytes);
    //     }

    //     return bytes.len;
    // }

    fn log_uci_in(self: *UCI, input: []const u8) !void {
        _ = self;
        std.log.debug("[INPUT] {s}", .{input});
        // if (self.log_file) |file| {
        //     try std.fmt.format(file.writer(), "[INPUT]  {s}\n", .{input});
        // }
    }

    // TODO send_uci_error
    pub fn log_uci_error(self: *UCI, comptime format: []const u8, args: anytype) !void {
        _ = self;
        std.log.err(format, args);

        // if (self.log_file) |file| {
        //     std.log.debug("log file is not null in log uci error", .{});
        //     try std.fmt.format(file.writer(), "[ERROR] " ++ format ++ "\n", args);
        // }
    }

    pub fn send_info(self: *UCI, res: search.SearchResult, pv: *const PV, timer: *Timer(), nodes: usize, depth: usize) !void {
        try self.writer.print("info depth {d} ", .{depth});

        if (mate_from_score(res.score)) |mate| {
            try self.writer.print("score mate {d} ", .{mate});
        } else {
            try self.writer.print("score cp {d} ", .{res.score});
        }

        const t_ns = try timer.elapsed_ns();
        const t_ms = t_ns / std.time.ns_per_ms;
        try self.writer.print("time {d} nodes {d} nps {d} pv ", .{ t_ms, nodes, nps(t_ns, nodes) });
        try pv.write_pv(self.writer);
        try self.writer.writeByte('\n');
        return self.writer.flush();
    }

    // TODO seems like there are a lack of free's in this
    pub fn run(self: *UCI, reader: *std.Io.Reader) !void {
        // TODO can this run in another thread?
        while (reader.takeDelimiterInclusive('\n')) |line| {
            // TODO maybe trim other chars? (\r?)
            const input = std.mem.trim(u8, line, " \n");
            try self.log_uci_in(input);

            const cmd = get_uci_command(input) catch {
                try self.log_uci_error("Unknown command: '{s}'", .{input});
                continue;
            };

            switch (cmd) {
                .uci => try self.handle_uci(),
                .isready => try self.handle_isready(),
                .ucinewgame => self.handle_ucinewgame(),
                .position => self.handle_position(input) catch |err| {
                    try self.log_uci_error("Invalid position command '{s}': {s}", .{ input, @errorName(err) });
                    continue;
                },
                .go => try self.handle_go(input),
                .quit => break,
            }
        } else |err| {
            switch (err) {
                error.EndOfStream => return,
                else => return err,
            }
        }
    }

    fn handle_uci(self: *UCI) !void {
        try self.writer.print("id name {s}\nid author {s}\nuciok\n", .{ BOT_NAME, AUTHOR });
        return self.writer.flush();
    }

    fn handle_isready(self: *UCI) !void {
        try self.writer.print("readyok\n", .{});
        return self.writer.flush();
    }

    pub fn handle_ucinewgame(self: *UCI) void {
        self.board = board.default_board();
        movegen.clear_repetitions();
        tt.clear();
    }

    pub fn handle_position(self: *UCI, input: []const u8) !void {
        self.board = pos: {
            if (std.mem.startsWith(u8, input, "position startpos")) break :pos board.default_board();
            if (!std.mem.startsWith(u8, input, "position fen")) return error.InvalidPositionCommand;
            const fen_start = "position fen".len;
            const fen_end = std.mem.indexOf(u8, input, " moves") orelse input.len;
            break :pos try board.board_from_fen(input[fen_start..fen_end]);
        };
        movegen.push_repetition(self.board.hash);

        const moves_start = (std.mem.indexOf(u8, input, " moves ") orelse return) + " moves ".len;
        self.board = try process_moves(self.board, input[moves_start..]);
    }

    pub fn handle_go(self: *UCI, input: []const u8) !void {
        //TODO handle options
        _ = input;

        // highly likley that there a many positions from the last
        // search that had incomplete bounds when the timer cut off
        // the search, clearing this increases the seach stablilty at
        // the cost of performance
        tt.clear();

        const res = try search.do_search(self);
        self.last_best_move = res.move;

        _ = try self.writer.write("bestmove ");
        try res.move.as_uci_str(self.writer);
        _ = try self.writer.write("\n");
        return self.writer.flush();
    }
};

fn nps(time_ns: u64, nodes: usize) f64 {
    const n: f64 = @floatFromInt(nodes);
    return std.math.floor((n * @as(f64, @floatFromInt(std.time.ns_per_s))) / @as(f64, @floatFromInt(time_ns)));
}

// returns mate in however many moves (not plies), negative if mated
// null if score isn't a mate score
fn mate_from_score(score: i32) ?i32 {
    if (score >= eval.CHECKMATE - search.MAX_DEPTH) {
        // +3 to the depth: +1 as all checkmates are odd, +2 to make the moves non-zero indexed
        return @divFloor(eval.CHECKMATE - score + 3, 2);
    }

    if (score <= -eval.CHECKMATE + search.MAX_DEPTH) {
        return @divFloor(@as(i32, @intCast(@abs(-eval.CHECKMATE + score))), 2);
    }

    return null;
}

fn get_uci_command(input: []const u8) !UciCommand {
    var it = std.mem.splitScalar(u8, input, ' ');
    const cmd = it.next() orelse return error.InvalidUciCommand;
    if (std.mem.eql(u8, cmd, "uci")) return .uci;
    if (std.mem.eql(u8, cmd, "isready")) return .isready;
    if (std.mem.eql(u8, cmd, "ucinewgame")) return .ucinewgame;
    if (std.mem.eql(u8, cmd, "position")) return .position;
    if (std.mem.eql(u8, cmd, "go")) return .go;
    return error.InvalidUciCommand;
}

pub fn process_moves(b: Board, moves: []const u8) !Board {
    var it = std.mem.splitScalar(u8, moves, ' ');
    var curr = b;
    while (it.next()) |s| {
        const m = try movegen.parse_uci_move_legal(curr, s);
        var next: Board = undefined;
        curr.copy_make(&next, m);
        curr = next;
        movegen.push_repetition(curr.hash);
    }

    return curr;
}
