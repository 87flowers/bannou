code: MoveCode,
id: u5,
src_coord: u8,
src_ptype: PieceType,
dest_coord: u8,
dest_ptype: PieceType,
capture_coord: u8,
capture_place: Place,
state: State,
mtype: MoveType,

pub fn isCapture(self: *const Move) bool {
    return !self.capture_place.isEmpty();
}

pub fn isPromotion(self: *const Move) bool {
    return self.src_ptype != self.dest_ptype;
}

pub fn isTactical(self: *const Move) bool {
    return self.isCapture() or self.isPromotion();
}

pub fn format(self: *const Move, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
    try writer.print("{}", .{self.code});
}

const MoveType = enum {
    normal,
    castle,
};

const Move = @This();
const std = @import("std");
const MoveCode = @import("MoveCode.zig");
const PieceType = @import("common.zig").PieceType;
const Place = @import("Board.zig").Place;
const State = @import("State.zig");
