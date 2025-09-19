const std = @import("std");

const OpeningTree = struct {};

const OpeningNode = struct {
    movelist: []const u8,
    reply: []const u8,
};
