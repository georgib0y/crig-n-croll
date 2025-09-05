const std = @import("std");
const board = @import("board.zig");
const UCI = @import("uci.zig").UCI;
const ZigTimer = @import("timer.zig").ZigTimer;

// pub const std_options = .{ .log_level = std.log.Level.debug };

fn new_log_file() !std.fs.File {
    const logdir = try std.fs.cwd().openDir("logs", .{});

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try std.fmt.format(fbs.writer(), "log_{d}", .{std.time.milliTimestamp()});
    return logdir.createFile(fbs.getWritten(), .{});
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const log_file = try new_log_file();
    const stdout = std.io.getStdOut().writer().any();
    var game = try UCI.init(allocator, board.default_board(), stdout, log_file);

    try game.run();
}
