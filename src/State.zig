/// bitboard of locations which pieces have been moved from
castle: u64,
/// enpassant square coordinate (if invalid then no enpassant square valid)
enpassant: u8,
/// for 50 move rule (in half-moves)
no_capture_clock: u8,
/// current move number (in half-moves)
ply: u16,
/// Zorbrist hash for position
hash: u64,

pub fn format(self: *const State, writer: anytype, board: *const Board) !void {
    // castling state
    var hasCastle = false;
    if (self.castle & castle_mask.wk == 0 and board.board[0x04].ptype == .k and board.board[0x07].ptype == .r) {
        try writer.print("K", .{});
        hasCastle = true;
    }
    if (self.castle & castle_mask.wq == 0 and board.board[0x04].ptype == .k and board.board[0x00].ptype == .r) {
        try writer.print("Q", .{});
        hasCastle = true;
    }
    if (self.castle & castle_mask.bk == 0 and board.board[0x74].ptype == .k and board.board[0x77].ptype == .r) {
        try writer.print("k", .{});
        hasCastle = true;
    }
    if (self.castle & castle_mask.bq == 0 and board.board[0x74].ptype == .k and board.board[0x70].ptype == .r) {
        try writer.print("q", .{});
        hasCastle = true;
    }
    if (!hasCastle) try writer.print("-", .{});
    if (coord.isValid(self.enpassant)) {
        try writer.print(" {s} ", .{coord.toString(self.enpassant)});
    } else {
        try writer.print(" - ", .{});
    }
    // move counts
    try writer.print("{} {}", .{ self.no_capture_clock, (self.ply >> 1) + 1 });
}

pub fn parseParts(active_color: Color, castle_str: []const u8, enpassant_str: []const u8, no_capture_clock_str: []const u8, ply_str: []const u8) !State {
    var result: State = .{
        .castle = ~@as(u64, 0),
        .enpassant = 0xFF,
        .no_capture_clock = undefined,
        .ply = undefined,
        .hash = undefined,
    };
    if (!std.mem.eql(u8, castle_str, "-")) {
        var i: usize = 0;
        while (i < castle_str.len and castle_str[i] != ' ') : (i += 1) {
            switch (castle_str[i]) {
                'K', 'H' => result.castle &= ~castle_mask.wk,
                'Q', 'A' => result.castle &= ~castle_mask.wq,
                'k', 'h' => result.castle &= ~castle_mask.bk,
                'q', 'a' => result.castle &= ~castle_mask.bq,
                else => return ParseError.InvalidChar,
            }
        }
    }
    if (!std.mem.eql(u8, enpassant_str, "-")) {
        if (enpassant_str.len != 2) return ParseError.InvalidLength;
        result.enpassant = try coord.fromString(enpassant_str[0..2].*);
    }
    result.no_capture_clock = try std.fmt.parseUnsigned(u8, no_capture_clock_str, 10);
    if (result.no_capture_clock > 200) return ParseError.OutOfRange;
    result.ply = try std.fmt.parseUnsigned(u16, ply_str, 10);
    if (result.ply < 1 or result.ply > 10000) return ParseError.OutOfRange;
    result.ply = (result.ply - 1) * 2 + @intFromEnum(active_color);
    return result;
}

const State = @This();
const std = @import("std");
const castle_mask = @import("castle_mask.zig");
const coord = @import("coord.zig");
const Board = @import("Board.zig");
const Color = @import("common.zig").Color;
const ParseError = @import("common.zig").ParseError;
