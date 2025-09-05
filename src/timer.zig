const std = @import("std");
const builtin = @import("builtin");
const config = @import("config");

pub fn Timer() type {
    if (comptime builtin.link_libc) {
        return struct {
            start: std.c.timespec,

            pub fn init() !@This() {
                var start: std.c.timespec = undefined;

                if (std.c.clock_gettime(.MONOTONIC, &start) == -1) {
                    return error.FailedToReadTimespec;
                }

                return .{ .start = start };
            }

            pub fn elapsed_ns(self: *@This()) !u64 {
                var now: std.c.timespec = undefined;

                if (std.c.clock_gettime(.MONOTONIC, &now) == -1) {
                    return error.FailedToReadTimespec;
                }

                var diff: u64 = @as(u64, @intCast(now.sec - self.start.sec)) * std.time.ns_per_s;
                diff += @intCast(now.nsec);
                diff -= @intCast(self.start.nsec);

                return diff;
            }
        };
    } else {
        return struct {
            timer: std.time.Timer,

            pub fn init() !@This() {
                return .{ .timer = try std.time.Timer.start() };
            }

            pub fn elapsed_ns(self: *@This()) !u64 {
                return self.timer.read();
            }
        };
    }
}
