code: MoveCode,
src_coord: u8,
src_place: Place,
dest_coord: u8,
dest_place: Place,
capture_coord: u8,
capture_place: Place,
enpassant: u8,
mtype: MoveType,

pub fn id(self: *const Move) u5 {
    assert(self.src_place.id == self.dest_place.id);
    return self.src_place.id;
}

pub fn srcPtype(self: *const Move) PieceType {
    return self.src_place.ptype;
}

pub fn destPtype(self: *const Move) PieceType {
    return self.dest_place.ptype;
}

pub fn isCapture(self: *const Move) bool {
    assert(!self.capture_place.isEmpty() == (self.mtype == .capture));
    return self.mtype == .capture;
}

pub fn isPromotion(self: *const Move) bool {
    return self.srcPtype() != self.destPtype();
}

pub fn isTactical(self: *const Move) bool {
    return self.isCapture() or self.isPromotion();
}

pub fn format(self: *const Move, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
    try writer.print("{}", .{self.code});
}

pub fn getNewState(self: *const Move, state: State) State {
    const color = Color.fromId(self.id());
    return switch (self.mtype) {
        .normal => .{
            .castle = state.castle | coord.toBit(self.src_coord) | coord.toBit(self.dest_coord),
            .enpassant = self.enpassant,
            .no_capture_clock = state.no_capture_clock + 1,
            .ply = state.ply + 1,
            .hash = state.hash ^
                zhash.move ^
                zhash.piece(color, self.srcPtype(), self.src_coord) ^
                zhash.piece(color, self.destPtype(), self.dest_coord) ^
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
                zhash.piece(color, self.srcPtype(), self.src_coord) ^
                zhash.piece(color, self.destPtype(), self.dest_coord) ^
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
