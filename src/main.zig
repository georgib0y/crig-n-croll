const std = @import("std");
const board = @import("board.zig");
const UCI = @import("uci.zig").UCI;
const ZigTimer = @import("timer.zig").ZigTimer;

pub const std_options = std.Options{ .log_level = std.log.Level.debug };

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

    // const log_file = try new_log_file();
    var stdout = std.fs.File.stdout();
    var wbuf: [1024]u8 = undefined;
    var writer = stdout.writer(&wbuf);
    var game = try UCI.init(allocator, &writer.interface, board.default_board());

    var stdin = std.fs.File.stdin();
    var rbuf: [1024]u8 = undefined;
    var reader = stdin.reader(&rbuf);
    try game.run(&reader.interface);
}
