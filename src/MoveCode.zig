code: u16,

pub const none = MoveCode{ .code = 0 };

pub fn castle_kingside(color: Color) MoveCode {
    const table = [2]MoveCode{
        MoveCode.parse("e1g1") catch unreachable,
        MoveCode.parse("e8g8") catch unreachable,
    };
    return table[@intFromEnum(color)];
}

pub fn castle_queenside(color: Color) MoveCode {
    const table = [2]MoveCode{
        MoveCode.parse("e1c1") catch unreachable,
        MoveCode.parse("e8c8") catch unreachable,
    };
    return table[@intFromEnum(color)];
}

pub fn make(src_ptype: PieceType, src_coord: u8, dest_ptype: PieceType, dest_coord: u8) MoveCode {
    return .{
        .code = @as(u16, coord.compress(src_coord)) << 9 |
            @as(u16, coord.compress(dest_coord)) << 3 |
            if (src_ptype != dest_ptype) @as(u16, @intFromEnum(dest_ptype)) else 0,
    };
}

pub fn promotion(self: MoveCode) PieceType {
    return @enumFromInt(self.code & 7);
}

pub fn isPromotion(self: MoveCode) bool {
    return self.promotion() != .none;
}

pub fn src(self: MoveCode) u8 {
    return coord.uncompress(@truncate(self.code >> 9));
}

pub fn dest(self: MoveCode) u8 {
    return coord.uncompress(@truncate(self.code >> 3));
}

pub fn format(self: MoveCode, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
    const ptype: PieceType = @enumFromInt(self.code & 7);
    try writer.print("{c}{c}{c}{c}", .{
        'a' + @as(u8, @truncate(self.code >> 9 & 7)),
        '1' + @as(u8, @truncate(self.code >> 12 & 7)),
        'a' + @as(u8, @truncate(self.code >> 3 & 7)),
        '1' + @as(u8, @truncate(self.code >> 6 & 7)),
    });
    if (ptype != .none) try writer.print("{c}", .{ptype.toChar(.black)});
}

pub fn parse(str: []const u8) ParseError!MoveCode {
    var result: u16 = 0;
    if (str.len < 4 or str.len > 5) return ParseError.InvalidLength;
    if (str[0] < 'a' or str[0] > 'h') return ParseError.InvalidChar;
    result |= @as(u16, str[0] - 'a') << 9;
    if (str[1] < '1' or str[1] > '8') return ParseError.InvalidChar;
    result |= @as(u16, str[1] - '1') << 12;
    if (str[2] < 'a' or str[2] > 'h') return ParseError.InvalidChar;
    result |= @as(u16, str[2] - 'a') << 3;
    if (str[3] < '1' or str[3] > '8') return ParseError.InvalidChar;
    result |= @as(u16, str[3] - '1') << 6;
    if (str.len > 4) {
        const ptype, _ = try PieceType.parse(str[4]);
        result |= @intFromEnum(ptype);
    }
    return .{ .code = result };
}

const std = @import("std");
const coord = @import("coord.zig");
const Color = @import("common.zig").Color;
const MoveCode = @import("MoveCode.zig");
const ParseError = @import("common.zig").ParseError;
const PieceType = @import("common.zig").PieceType;
