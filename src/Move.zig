code: MoveCode,
id: u5,
src_coord: u8,
src_ptype: PieceType,
dest_coord: u8,
dest_ptype: PieceType,
capture_coord: u8,
capture_place: Place,
enpassant: u8,
mtype: MoveType,

pub fn isCapture(self: *const Move) bool {
    assert(!self.capture_place.isEmpty() == (self.mtype == .capture));
    return self.mtype == .capture;
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

pub fn getNewState(self: *const Move, state: State) State {
    const color = Color.fromId(self.id);
    return switch (self.mtype) {
        .normal => .{
            .castle = state.castle | coord.toBit(self.src_coord) | coord.toBit(self.dest_coord),
            .enpassant = self.enpassant,
            .no_capture_clock = state.no_capture_clock + 1,
            .ply = state.ply + 1,
            .hash = state.hash ^
                zhash.move ^
                zhash.piece(color, self.src_ptype, self.src_coord) ^
                zhash.piece(color, self.dest_ptype, self.dest_coord) ^
                zhash.enpassant(state.enpassant) ^
                zhash.enpassant(self.enpassant) ^
                zhash.castle(state.castle) ^
                zhash.castle(state.castle | coord.toBit(self.src_coord) | coord.toBit(self.dest_coord)),
        },
        .castle => .{
            .castle = state.castle | coord.toBit(self.src_coord) | coord.toBit(self.code.src()),
            .enpassant = 0xFF,
            .no_capture_clock = state.no_capture_clock + 1,
            .ply = state.ply + 1,
            .hash = state.hash ^
                zhash.move ^
                zhash.piece(color, .k, self.code.src()) ^
                zhash.piece(color, .k, self.code.dest()) ^
                zhash.piece(color, .r, self.src_coord) ^
                zhash.piece(color, .r, self.dest_coord) ^
                zhash.enpassant(state.enpassant) ^
                zhash.castle(state.castle) ^
                zhash.castle(state.castle | coord.toBit(self.src_coord) | coord.toBit(self.code.src())),
        },
        .capture => .{
            .castle = state.castle | coord.toBit(self.src_coord) | coord.toBit(self.dest_coord),
            .enpassant = self.enpassant,
            .no_capture_clock = 0,
            .ply = state.ply + 1,
            .hash = state.hash ^
                zhash.move ^
                zhash.piece(color, self.src_ptype, self.src_coord) ^
                zhash.piece(color, self.dest_ptype, self.dest_coord) ^
                zhash.piece(color.invert(), self.capture_place.ptype, self.capture_coord) ^
                zhash.enpassant(state.enpassant) ^
                zhash.castle(state.castle) ^
                zhash.castle(state.castle | coord.toBit(self.src_coord) | coord.toBit(self.dest_coord)),
        },
    };
}

const MoveType = enum {
    normal,
    castle,
    capture,
};

const Move = @This();
const std = @import("std");
const assert = std.debug.assert;
const coord = @import("coord.zig");
const zhash = @import("zhash.zig");
const Color = @import("common.zig").Color;
const MoveCode = @import("MoveCode.zig");
const PieceType = @import("common.zig").PieceType;
const Place = @import("Board.zig").Place;
const State = @import("State.zig");
