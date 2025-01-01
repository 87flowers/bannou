code: MoveCode,
src_place: Place,
dest_place: Place,
capture_coord: u8,
capture_place: Place,
enpassant: u8,
mtype: MoveType,

test {
    comptime assert(@sizeOf(Move) == 8);
}

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

fn srcBit(self: *const Move) u64 {
    return @as(u64, 1) << self.code.compressedSrc();
}

fn destBit(self: *const Move) u64 {
    return @as(u64, 1) << self.code.compressedDest();
}

pub inline fn getNewState(self: *const Move, state: State) State {
    const color = Color.fromId(self.id());
    switch (self.mtype) {
        .normal => return .{
            .castle = state.castle | self.srcBit() | self.destBit(),
            .enpassant = self.enpassant,
            .no_capture_clock = state.no_capture_clock + 1,
            .ply = state.ply + 1,
            .hash = state.hash ^
                zhash.move ^
                zhash.piece(color, self.srcPtype(), self.code.compressedSrc()) ^
                zhash.piece(color, self.destPtype(), self.code.compressedDest()) ^
                zhash.enpassant(state.enpassant) ^
                zhash.enpassant(self.enpassant) ^
                zhash.castle(state.castle) ^
                zhash.castle(state.castle | self.srcBit() | self.destBit()),
        },
        .castle => {
            const king_src = self.code.compressedSrc();
            const king_dest = self.code.compressedDest();
            const rook_src: u6, const rook_dest: u6 = getCastlingRookMove(king_dest);
            return .{
                .castle = state.castle | color.frontRankBits(),
                .enpassant = 0xFF,
                .no_capture_clock = state.no_capture_clock + 1,
                .ply = state.ply + 1,
                .hash = state.hash ^
                    zhash.move ^
                    zhash.piece(color, .k, king_src) ^
                    zhash.piece(color, .k, king_dest) ^
                    zhash.piece(color, .r, rook_src) ^
                    zhash.piece(color, .r, rook_dest) ^
                    zhash.enpassant(state.enpassant) ^
                    zhash.castle(state.castle) ^
                    zhash.castle(state.castle | color.frontRankBits()),
            };
        },
        .capture => return .{
            .castle = state.castle | self.srcBit() | self.destBit(),
            .enpassant = self.enpassant,
            .no_capture_clock = 0,
            .ply = state.ply + 1,
            .hash = state.hash ^
                zhash.move ^
                zhash.piece(color, self.srcPtype(), self.code.compressedSrc()) ^
                zhash.piece(color, self.destPtype(), self.code.compressedDest()) ^
                zhash.piece(color.invert(), self.capture_place.ptype, coord.compress(self.capture_coord)) ^
                zhash.enpassant(state.enpassant) ^
                zhash.castle(state.castle) ^
                zhash.castle(state.castle | self.srcBit() | self.destBit()),
        },
    }
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
const getCastlingRookMove = @import("common.zig").getCastlingRookMove;
const zhash = @import("zhash.zig");
const Color = @import("common.zig").Color;
const MoveCode = @import("MoveCode.zig");
const PieceType = @import("common.zig").PieceType;
const Place = @import("Board.zig").Place;
const State = @import("State.zig");
