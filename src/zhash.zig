pub const move = 0x446c_92da_bed9_5f78;

const table: [2 * 8 * 0x80]u64 = blk: {
    @setEvalBranchQuota(1000000);
    var prng = Prng.init();
    var result: [2 * 8 * 0x80]u64 = undefined;
    for (&result) |*hash| hash.* = prng.next();
    break :blk result;
};

pub fn piece(color: Color, ptype: PieceType, coord: u8) u64 {
    const index = @as(usize, @intFromEnum(ptype)) << 8 | @as(usize, @intFromEnum(color)) << 7 | @as(usize, coord);
    return table[index];
}

pub fn castle(c: u64) u64 {
    return std.math.rotl(u64, c & castle_mask.any, 16);
}

const std = @import("std");
const castle_mask = @import("castle_mask.zig");
const Color = @import("common.zig").Color;
const PieceType = @import("common.zig").PieceType;
const Prng = @import("Prng.zig");
