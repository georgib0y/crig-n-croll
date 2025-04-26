const std = @import("std");
const board = @import("board.zig");
const uci = @import("uci.zig");

pub const std_options = .{ .log_level = std.log.Level.debug };

fn new_log_file() !std.fs.File {
    const logdir = try std.fs.cwd().openDir("logs", .{});

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try std.fmt.format(fbs.writer(), "log_{d}", .{std.time.milliTimestamp()});
    return logdir.createFile(fbs.getWritten(), .{});
}

pub fn main() !void {
    var game = uci.UCI{ .board = board.default_board(), .log_file = try new_log_file() };
    try game.run();
}
