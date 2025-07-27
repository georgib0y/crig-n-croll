const std = @import("std");
const File = std.fs.File;
const board = @import("board.zig");
const Board = board.Board;
const tt = @import("tt.zig");
const search = @import("search.zig");
const movegen = @import("movegen.zig");
const eval = @import("eval.zig");

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
    log_file: ?std.fs.File,
    generic_writer: std.io.GenericWriter(*UCI, anyerror, writeFn),

    pub fn init(allocator: std.mem.Allocator, b: Board, log_file: ?std.fs.File) !*UCI {
        var uci = try allocator.create(UCI);
        uci.board = b;
        uci.log_file = log_file;
        uci.generic_writer = std.io.GenericWriter(*UCI, anyerror, writeFn){ .context = uci };
        return uci;
    }

    pub fn deinit(self: *UCI, allocator: std.mem.Allocator) void {
        allocator.destroy(self);
    }

    fn writeFn(self: *UCI, bytes: []const u8) !usize {
        try std.io.getStdOut().writeAll(bytes);
        if (self.log_file) |file| {
            _ = try file.writeAll(bytes);
        }

        return bytes.len;
    }

    pub fn writer(self: *UCI) std.io.AnyWriter {
        return self.generic_writer.any();
    }

    fn log_uci_in(self: *UCI, input: []const u8) !void {
        std.log.debug("[INPUT] {s}", .{input});
        if (self.log_file) |file| {
            try std.fmt.format(file.writer(), "[INPUT]  {s}\n", .{input});
        }
    }

    // TODO send_uci_error
    pub fn log_uci_error(self: *UCI, comptime format: []const u8, args: anytype) !void {
        std.log.err(format, args);

        if (self.log_file) |file| {
            std.log.debug("log file is not null in log uci error", .{});
            try std.fmt.format(file.writer(), "[ERROR] " ++ format ++ "\n", args);
        }
    }

    pub fn send_info(self: *UCI, res: search.SearchResult, timer: *std.time.Timer, nodes: usize, depth: usize) !void {
        const w = self.writer();
        try std.fmt.format(w, "info depth {d} ", .{depth});

        if (mate_from_score(res.score)) |mate| {
            try std.fmt.format(w, "score mate {d} ", .{mate});
        } else {
            try std.fmt.format(w, "score cp {d} ", .{res.score});
        }

        const t_ns = timer.read();
        const t_ms = t_ns / std.time.ns_per_ms;
        try std.fmt.format(w, "time {d} nodes {d} nps {d} pv ", .{ t_ms, nodes, nps(t_ns, nodes) });
        try tt.write_pv(w, &self.board, depth);
        try w.writeByte('\n');
    }

    // TODO seems like there are a lack of free's in this
    pub fn run(self: *UCI) !void {
        var in = std.io.getStdIn().reader();
        var buf: [4096]u8 = undefined;
        // TODO can this run in another thread?
        while (try in.readUntilDelimiterOrEof(&buf, '\n')) |line| {
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
        }
    }

    fn handle_uci(self: *UCI) !void {
        return std.fmt.format(self.writer(), "id name {s}\nid author {s}\nuciok\n", .{ BOT_NAME, AUTHOR });
    }

    fn handle_isready(self: *UCI) !void {
        return std.fmt.format(self.writer(), "readyok\n", .{});
    }

    fn handle_ucinewgame(self: *UCI) void {
        self.board = board.default_board();
        movegen.clear_repetitions();
        tt.clear();
    }

    fn handle_position(self: *UCI, input: []const u8) !void {
        var pos: Board = pos: {
            if (std.mem.startsWith(u8, input, "position startpos")) break :pos board.default_board();
            if (!std.mem.startsWith(u8, input, "position fen")) return error.InvalidPositionCommand;
            const fen_start = "position fen".len;
            const fen_end = std.mem.indexOf(u8, input, " moves") orelse input.len;
            break :pos try board.board_from_fen(input[fen_start..fen_end]);
        };
        defer self.board = pos;
        movegen.push_repetition(pos.hash);

        const moves_start = (std.mem.indexOf(u8, input, " moves ") orelse return) + " moves ".len;
        pos = try process_moves(pos, input[moves_start..]);
    }

    fn handle_go(self: *UCI, input: []const u8) !void {
        //TODO handle options
        _ = input;

        // highly likley that there a many positions from the last
        // search that had incomplete bounds when the timer cut off
        // the search, clearing this increases the seach stablilty at
        // the cost of performance
        tt.clear();

        const res = try search.do_search(self);

        const w = self.writer();
        _ = try w.write("bestmove ");
        try res.move.as_uci_str(w);
        _ = try w.write("\n");
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

pub fn process_moves(b: Board, move_str: []const u8) !Board {
    var it = std.mem.splitScalar(u8, move_str, ' ');
    var curr = b;
    while (it.next()) |s| {
        const m = try movegen.new_move_from_uci(s, &curr);
        var next: Board = undefined;
        curr.copy_make(&next, m);
        curr = next;
        movegen.push_repetition(curr.hash);
    }

    return curr;
}
