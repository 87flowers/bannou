hash: Hash,
best_move: MoveCode,
depth: u8,
bound: Bound,
score: i32,

pub const empty = TTEntry{
    .hash = 0,
    .best_move = .{ .code = 0 },
    .depth = undefined,
    .bound = undefined,
    .score = undefined,
};

const Bound = enum { lower, exact, upper };

test {
    comptime assert(@sizeOf(TTEntry) == 16);
}

const TTEntry = @This();
const std = @import("std");
const assert = std.debug.assert;
const Hash = @import("zhash.zig").Hash;
const MoveCode = @import("MoveCode.zig");
