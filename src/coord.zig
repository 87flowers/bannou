pub fn toString(coord: u8) [2]u8 {
    return .{ 'a' + (coord & 0xF), '1' + (coord >> 4) };
}

pub fn fromString(str: [2]u8) ParseError!u8 {
    return try fileFromChar(str[0]) + try rankFromChar(str[1]);
}

pub fn fileFromChar(ch: u8) ParseError!u8 {
    if (ch < 'a' or ch > 'h') return ParseError.InvalidChar;
    return ch - 'a';
}

pub fn rankFromChar(ch: u8) ParseError!u8 {
    if (ch < '1' or ch > '8') return ParseError.InvalidChar;
    return (ch - '1') << 4;
}

test toString {
    for (0..256) |i| {
        const coord: u8 = @intCast(i);
        if (isValid(coord)) {
            try std.testing.expectEqual(coord, try fromString(toString(coord)));
        }
    }
}

pub fn compress(coord: u8) u6 {
    assert(isValid(coord));
    return @intCast((coord + (coord & 7)) >> 1);
}

pub fn uncompress(comp: u6) u8 {
    return @as(u8, comp & 0b111000) + @as(u8, comp);
}

test compress {
    for (0..256) |i| {
        const coord: u8 = @intCast(i);
        if (isValid(coord)) {
            try std.testing.expectEqual(coord, uncompress(compress(coord)));
        }
    }
}

pub fn toBit(coord: u8) u64 {
    return @as(u64, 1) << compress(coord);
}

pub fn isValid(coord: u8) bool {
    return (coord & 0x88) == 0;
}

pub const diag_dir = [4]u8{ 0xEF, 0xF1, 0x0F, 0x11 };
pub const ortho_dir = [4]u8{ 0xF0, 0xFF, 0x01, 0x10 };
pub const all_dir = diag_dir ++ ortho_dir;
pub const knight_dir = [8]u8{ 0xDF, 0xE1, 0xEE, 0x0E, 0xF2, 0x12, 0x1F, 0x21 };

const std = @import("std");
const assert = std.debug.assert;
const ParseError = @import("common.zig").ParseError;
