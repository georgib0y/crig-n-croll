const std = @import("std");
const board = @import("board.zig");
const uci = @import("uci.zig");
const UCI = uci.UCI;
const perft = @import("perft.zig");
// const PosixTimer = @import("timer.zig").PosixTimer;
const ZigTimer = @import("timer.zig").ZigTimer;
const util = @import("util.zig");

pub const std_options: std.Options = .{
    .page_size_min = 16384,
    .page_size_max = 16384,
};

const C = @cImport({
    @cInclude("jni.h");
    @cInclude("log.h");
});

// TODO these are functions not supported in andoid libc !!
pub export fn __errno_location() callconv(.c) ?*c_int {
    return null;
}

// TODO these are functions not supported in andoid libc !!
pub export fn getcontext(ucp: *anyopaque) callconv(.c) c_int {
    _ = ucp;
    return -99;
}

// TODO these are functions not supported in andoid libc !!
pub export fn setcontext(ucp: *const anyopaque) callconv(.c) c_int {
    _ = ucp;
    return -98;
}

pub fn drainToAndroid(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
    var bArray = std.ArrayList(u8).empty;
    defer bArray.deinit(allocator);

    bArray.appendSlice(allocator, w.buffered()) catch return std.Io.Writer.Error.WriteFailed;

    for (data[0 .. data.len - 1]) |bytes|
        bArray.appendSlice(allocator, bytes) catch return std.Io.Writer.Error.WriteFailed;

    for (0..splat) |_|
        bArray.appendSlice(allocator, data[data.len - 1]) catch return std.Io.Writer.Error.WriteFailed;

    bArray.append(allocator, 0) catch return std.Io.Writer.Error.WriteFailed;

    const str: [:0]u8 = @ptrCast(bArray.items);

    if (C.__android_log_print(C.ANDROID_LOG_DEBUG, "UCI", str) != 1) {
        return std.Io.Writer.Error.WriteFailed;
    }

    w.end = 0;

    return str.len;
}

var androidLogBuffer: [2048]u8 = undefined;
const androidLogVtable: std.Io.Writer.VTable = .{
    .drain = drainToAndroid,
};
var androidLogWriter = std.Io.Writer{
    .vtable = &androidLogVtable,
    .buffer = &androidLogBuffer,
    .end = 0,
};
// const androidLogWriter = std.io.GenericWriter(void, anyerror, writeLogToAndroid){
//     .context = {},
// };

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const allocator = arena.allocator();

fn new_string(env: *C.JNIEnv, str: [:0]const u8) C.jstring {
    return env.*.*.NewStringUTF.?(env, str[0..str.len :0]);
}

fn get_string(env: *C.JNIEnv, str: C.jstring) []const u8 {
    return std.mem.span(env.*.*.GetStringUTFChars.?(env, str, 0));
}

fn throw_uci_exception(
    env: *C.JNIEnv,
    err: anyerror,
    description: ?[]const u8,
) i32 {
    const class_name: [:0]const u8 = "com/github/georgib0y/crigapp/UciException";
    const class =
        env.*.*.FindClass.?(env, class_name) orelse std.debug.panic("cannot find class: {s}", .{class_name});

    var buf: [512]u8 = undefined;
    var msg: []u8 = undefined;
    if (description) |desc| {
        msg = std.fmt.bufPrint(&buf, "{s}: {s}", .{
            @errorName(err),
            desc,
        }) catch std.debug.panic("not enough space in buf for exception messsage", .{});
    } else {
        msg = std.fmt.bufPrint(&buf, "{s}", .{
            @errorName(err),
        }) catch std.debug.panic("not enough space in buf for exception messsage", .{});
    }

    // write a sentinel at the end of msg
    buf[msg.len] = 0;
    return env.*.*.ThrowNew.?(env, class, buf[0..msg.len :0]);
}

pub export fn Java_com_github_georgib0y_crigapp_UCI_initUci(env: *C.JNIEnv, this: C.jobject) callconv(.c) ?*UCI {
    _ = this;
    return UCI.init(allocator, &androidLogWriter, board.default_board()) catch |err| {
        _ = throw_uci_exception(env, err, "could not init uci");
        return null;
    };
}

pub export fn Java_com_github_georgib0y_crigapp_UCI_uciNewGame(
    env: *C.JNIEnv,
    this: C.jobject,
    uci_instance: *UCI,
) callconv(.c) void {
    _ = env;
    _ = this;
    uci_instance.handle_ucinewgame();
}

// returns -1 if there are no bad positions, else returns the idx of the bad move
pub export fn Java_com_github_georgib0y_crigapp_UCI_validatePosition(
    env: *C.JNIEnv,
    this: C.jobject,
    pos_str: C.jstring,
) callconv(.c) C.jint {
    _ = this;

    if (pos_str == null) {
        _ = throw_uci_exception(env, error.NullPosStr, null);
        return -99;
    }

    const pos_slice = get_string(env, pos_str);
    return uci.validate_moves(pos_slice) orelse -1;
}

// position is the position string as the uci protocol expects
pub export fn Java_com_github_georgib0y_crigapp_UCI_searchPosition(
    env: *C.JNIEnv,
    this: C.jobject,
    uci_instance: *UCI,
    pos_str: C.jstring,
) callconv(.c) C.jstring {
    _ = this;

    if (pos_str == null) {
        _ = throw_uci_exception(env, error.NullPosStr, null);
        return null;
    }

    const pos_slice = get_string(env, pos_str);
    uci_instance.handle_position(pos_slice) catch |err| {
        _ = throw_uci_exception(env, err, "could not set position");
        return null;
    };

    uci_instance.handle_go("go") catch |err| {
        _ = throw_uci_exception(env, err, "error while searching");
        return null;
    };

    var best_move: [100]u8 = undefined;
    var fixed = std.io.Writer.fixed(&best_move);
    // const writer = fbs.writer();

    if (uci_instance.last_best_move == null) {
        _ = throw_uci_exception(env, error.EmptyLastBestMove, null);
        return null;
    }

    uci_instance.last_best_move.?.as_uci_str(&fixed) catch |err| {
        _ = throw_uci_exception(env, err, "error writing best move");
        return null;
    };

    // write sentinel at bm end
    _ = fixed.write(&.{0}) catch |err| {
        _ = throw_uci_exception(env, err, "error writing bm sentinel");
        return null;
    };

    const bm_str: [:0]u8 = @ptrCast(fixed.buffered());
    // return new_string(env, fbs.getWritten());
    return env.*.*.NewStringUTF.?(env, bm_str);
    // return new_string(env, "new string");
}

pub export fn Java_com_github_georgib0y_crigapp_UCI_logUciPosition(
    env: *C.JNIEnv,
    this: C.jobject,
    uci_instance: *UCI,
    pos_str: C.jstring,
) void {
    _ = this;

    uci_instance.handle_position(get_string(env, pos_str)) catch |err| {
        _ = throw_uci_exception(env, err, "could not set position for logging");
        return;
    };

    util.display_board(uci_instance.board, &androidLogWriter) catch |err| {
        _ = throw_uci_exception(env, err, "failed to write uci board");
    };

    androidLogWriter.flush() catch |err| {
        _ = throw_uci_exception(env, err, "failed to flush uci board");
    };
}
