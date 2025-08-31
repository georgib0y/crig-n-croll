const std = @import("std");
const board = @import("board.zig");
const UCI = @import("uci.zig").UCI;
const perft = @import("perft.zig");

const AppUci = UCI(std.io.NullWriter);

const C = @cImport({
    @cInclude("jni.h");
});

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const allocator = arena.allocator();

fn new_string(env: *C.JNIEnv, str: [:0]const u8) C.jstring {
    return env.*.*.NewStringUTF.?(env, str[0..str.len :0]);
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

pub export fn Java_com_github_georgib0y_crigapp_UCI_initUci(
    env: *C.JNIEnv,
    this: C.jobject,
) ?*AppUci {
    _ = this;
    return AppUci.init(allocator, board.default_board(), std.io.null_writer, null) catch |err| {
        _ = throw_uci_exception(env, err, "could not init uci");
        return null;
    };
}

pub export fn Java_com_github_georgib0y_crigapp_UCI_uciNewGame(
    env: *C.JNIEnv,
    this: C.jobject,
    uci: *AppUci,
) callconv(.C) void {
    _ = env;
    _ = this;
    uci.handle_ucinewgame();
}

// position is the position string as the uci protocol expects
pub export fn Java_com_github_georgib0y_crigapp_UCI_sendPosition(
    env: *C.JNIEnv,
    this: C.jobject,
    uci: *AppUci,
    pos_str: C.jstring,
) callconv(.C) C.jstring {
    _ = this;

    if (pos_str == null) {
        _ = throw_uci_exception(env, error.NullPosStr, null);
        return null;
    }

    const pos_slice: []const u8 = std.mem.span(env.*.*.GetStringUTFChars.?(env, pos_str, 0));
    uci.handle_position(pos_slice) catch |err| {
        _ = throw_uci_exception(env, err, "could not set position");
        return null;
    };

    uci.handle_go("go") catch |err| {
        _ = throw_uci_exception(env, err, "error while searching");
        return null;
    };

    var best_move: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&best_move);
    const writer = fbs.writer();

    if (uci.last_best_move == null) {
        _ = throw_uci_exception(env, error.EmptyLastBestMove, null);
        return null;
    }

    uci.last_best_move.?.as_uci_str(writer) catch |err| {
        _ = throw_uci_exception(env, err, "error writing best move");
        return null;
    };

    // write sentinel at bm end
    const end = fbs.getPos() catch |err| {
        _ = throw_uci_exception(env, err, null);
        return null;
    };
    best_move[end] = 0;

    // return new_string(env, fbs.getWritten());
    return env.*.*.NewStringUTF.?(env, best_move[0..end :0]);
    // return new_string(env, "new string");
}
