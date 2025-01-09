pub const max_game_ply = 1024;
pub const max_legal_moves = 256;
pub const max_search_ply = 127;

pub const ParseError = error{
    InvalidChar,
    InvalidLength,
    DuplicateKing,
    TooManyPieces,
    OutOfRange,
};

pub const PieceType = enum(u3) {
    none = 0,
    k = 6,
    q = 5,
    r = 4,
    b = 3,
    n = 2,
    p = 1,

    pub fn toChar(self: PieceType, color: Color) u8 {
        return @as(u8, switch (self) {
            .none => '.',
            .k => switch (color) {
                .black => 'k',
                .white => 'K',
            },
            .q => switch (color) {
                .black => 'q',
                .white => 'Q',
            },
            .r => switch (color) {
                .black => 'r',
                .white => 'R',
            },
            .b => switch (color) {
                .black => 'b',
                .white => 'B',
            },
            .n => switch (color) {
                .black => 'n',
                .white => 'N',
            },
            .p => switch (color) {
                .black => 'p',
                .white => 'P',
            },
        });
    }

    pub fn parseUncolored(ch: u8) ParseError!PieceType {
        return switch (ch) {
            'K' => .k,
            'Q' => .q,
            'R' => .r,
            'B' => .b,
            'N' => .n,
            'P' => .p,
            else => ParseError.InvalidChar,
        };
    }

    pub fn parse(ch: u8) ParseError!struct { PieceType, Color } {
        return switch (ch) {
            'K' => .{ .k, .white },
            'k' => .{ .k, .black },
            'Q' => .{ .q, .white },
            'q' => .{ .q, .black },
            'R' => .{ .r, .white },
            'r' => .{ .r, .black },
            'B' => .{ .b, .white },
            'b' => .{ .b, .black },
            'N' => .{ .n, .white },
            'n' => .{ .n, .black },
            'P' => .{ .p, .white },
            'p' => .{ .p, .black },
            else => ParseError.InvalidChar,
        };
    }
};

pub const Color = enum(u1) {
    white = 0,
    black = 1,

    pub fn fromId(id: u5) Color {
        return @enumFromInt(id >> 4);
    }

    pub fn invert(self: Color) Color {
        return @enumFromInt(~@intFromEnum(self));
    }

    pub fn frontRankBits(self: Color) u64 {
        return switch (self) {
            .white => 0x00_00_00_00_00_00_00_FF,
            .black => 0xFF_00_00_00_00_00_00_00,
        };
    }

    pub fn backRank(self: Color) u8 {
        return @as(u8, @bitCast(-@as(i8, @intFromEnum(self)))) & 0x70;
    }

    pub fn idBase(self: Color) u5 {
        return @as(u5, @intFromEnum(self)) << 4;
    }

    pub fn toRankInvertMask(color: Color) u8 {
        return @as(u8, @bitCast(-@as(i8, @intFromEnum(color)))) & 0x70;
    }

    pub fn toChar(self: Color) u8 {
        return switch (self) {
            .white => 'w',
            .black => 'b',
        };
    }

    pub fn format(self: Color, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{c}", .{self.toChar()});
    }

    pub fn parse(ch: u8) ParseError!Color {
        return switch (ch) {
            'w' => .white,
            'b' => .black,
            else => ParseError.InvalidChar,
        };
    }
};

pub fn getPawnCaptures(color: Color, src: u8) [2]u8 {
    const invert = color.toRankInvertMask();
    const isrc = src ^ invert;
    return [2]u8{ (isrc + 0x0F) ^ invert, (isrc + 0x11) ^ invert };
}

pub fn getCastlingRookMove(compressed_king_dest: u6) [2]u6 {
    const king_rank = compressed_king_dest & 0o70;
    const king_file = compressed_king_dest & 0o07;
    return switch (king_file) {
        2 => .{ king_rank | 0, king_rank | 3 },
        6 => .{ king_rank | 7, king_rank | 5 },
        else => unreachable,
    };
}

const std = @import("std");
