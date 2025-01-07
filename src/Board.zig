pieces: [32]PieceType,
where: [32]u8,
board: [128]Place,
state: State,
active_color: Color,

pub fn emptyBoard() Board {
    return comptime .{
        .pieces = [1]PieceType{.none} ** 32,
        .where = undefined,
        .board = [1]Place{Place.empty} ** 128,
        .state = .{
            .castle = 0,
            .enpassant = 0xff,
            .no_capture_clock = 0,
            .ply = 0,
        },
        .active_color = .white,
    };
}

pub fn defaultBoard() Board {
    return comptime blk: {
        @setEvalBranchQuota(10000);
        var result = emptyBoard();
        result.place(0x01, .r, 0x00);
        result.place(0x03, .n, 0x01);
        result.place(0x05, .b, 0x02);
        result.place(0x07, .q, 0x03);
        result.place(0x00, .k, 0x04);
        result.place(0x06, .b, 0x05);
        result.place(0x04, .n, 0x06);
        result.place(0x02, .r, 0x07);
        result.place(0x08, .p, 0x10);
        result.place(0x09, .p, 0x11);
        result.place(0x0A, .p, 0x12);
        result.place(0x0B, .p, 0x13);
        result.place(0x0C, .p, 0x14);
        result.place(0x0D, .p, 0x15);
        result.place(0x0E, .p, 0x16);
        result.place(0x0F, .p, 0x17);
        result.place(0x11, .r, 0x70);
        result.place(0x13, .n, 0x71);
        result.place(0x15, .b, 0x72);
        result.place(0x17, .q, 0x73);
        result.place(0x10, .k, 0x74);
        result.place(0x16, .b, 0x75);
        result.place(0x14, .n, 0x76);
        result.place(0x12, .r, 0x77);
        result.place(0x18, .p, 0x60);
        result.place(0x19, .p, 0x61);
        result.place(0x1A, .p, 0x62);
        result.place(0x1B, .p, 0x63);
        result.place(0x1C, .p, 0x64);
        result.place(0x1D, .p, 0x65);
        result.place(0x1E, .p, 0x66);
        result.place(0x1F, .p, 0x67);
        break :blk result;
    };
}

pub fn place(self: *Board, id: u5, ptype: PieceType, where: u8) void {
    assert(self.board[where].isEmpty() and self.pieces[id] == .none);
    self.pieces[id] = ptype;
    self.where[id] = where;
    self.board[where] = Place{ .ptype = ptype, .id = id };
}

pub fn move(self: *Board, old: *Board, m: Move, old_hash: Hash) Hash {
    var hash: Hash = undefined;
    self.pieces = old.pieces;
    self.where = old.where;
    self.board = old.board;
    switch (m.mtype) {
        .normal => {
            assert(self.board[m.code.src()].eql(m.src_place));
            self.board[m.code.src()] = Place.empty;
            self.board[m.code.dest()] = m.dest_place;
            self.where[m.id()] = m.code.dest();
            self.pieces[m.id()] = m.destPtype();
            self.state, hash = m.getNewState(old.state, old_hash);
        },
        .capture => {
            assert(self.pieces[m.capture_place.id] == m.capture_place.ptype);
            assert(self.board[m.capture_coord].eql(m.capture_place));
            self.pieces[m.capture_place.id] = .none;
            self.board[m.capture_coord] = Place.empty;
            assert(self.board[m.code.src()].eql(m.src_place));
            self.board[m.code.src()] = Place.empty;
            self.board[m.code.dest()] = m.dest_place;
            self.where[m.id()] = m.code.dest();
            self.pieces[m.id()] = m.destPtype();
            self.state, hash = m.getNewState(old.state, old_hash);
        },
        .castle => {
            assert(m.srcPtype() == .r and m.destPtype() == .r);
            const king_src = m.code.compressedSrc();
            const king_dest = m.code.compressedDest();
            const rook_src: u6, const rook_dest: u6 = getCastlingRookMove(king_dest);
            self.board[coord.uncompress(king_src)] = Place.empty;
            self.board[coord.uncompress(rook_src)] = Place.empty;
            self.board[coord.uncompress(king_dest)] = Place{ .ptype = .k, .id = m.id() & 0x10 };
            self.board[coord.uncompress(rook_dest)] = Place{ .ptype = .r, .id = m.id() };
            self.where[m.id() & 0x10] = coord.uncompress(king_dest);
            self.where[m.id()] = coord.uncompress(rook_dest);
            self.state, hash = m.getNewState(old.state, old_hash);
        },
    }
    self.active_color = old.active_color.invert();
    return hash;
}

pub fn makeMoveByCode(self: *Board, old: *Board, code: MoveCode, old_hash: Hash) ?Hash {
    const p = old.board[code.src()];
    if (p.isEmpty()) return null;

    var moves = MoveList{};
    moves.generateMovesForPiece(old, .any, p.id);
    for (0..moves.size) |i| {
        const m = moves.moves[i];
        if (std.meta.eql(m.code, code)) {
            return self.move(old, m, old_hash);
        }
    }
    return null;
}

pub fn moveNull(self: *Board, old: *Board, old_hash: Hash) Hash {
    self.pieces = old.pieces;
    self.where = old.where;
    self.board = old.board;
    self.state.castle = old.state.castle;
    self.state.enpassant = 0xFF;
    self.state.no_capture_clock = 0;
    self.state.ply = old.state.ply + 1;
    self.active_color = old.active_color.invert();
    return old_hash ^ zhash.move ^ zhash.enpassant(old.state.enpassant);
}

/// This MUST be checked after making a move on the board.
pub fn isValid(self: *const Board) bool {
    // Ensure player that just made a move is not in check!
    const move_color = self.active_color.invert();
    const king_id = move_color.idBase();
    return !self.isAttacked(self.where[king_id], move_color);
}

pub fn isInCheck(self: *const Board) bool {
    const king_id = self.active_color.idBase();
    return self.isAttacked(self.where[king_id], self.active_color);
}

pub fn isAttacked(self: *const Board, target: u8, friendly: Color) bool {
    const enemy_color = friendly.invert();
    const id_base = enemy_color.idBase();
    for (0..16) |id_index| {
        const id: u5 = @intCast(id_base + id_index);
        const enemy = self.where[id];
        switch (self.pieces[id]) {
            .none => {},
            .k => for (coord.all_dir) |dir| if (target == enemy +% dir) return true,
            .q => if (self.isVisibleBySlider(coord.all_dir, enemy, target)) return true,
            .r => if (self.isVisibleBySlider(coord.ortho_dir, enemy, target)) return true,
            .b => if (self.isVisibleBySlider(coord.diag_dir, enemy, target)) return true,
            .n => for (coord.knight_dir) |dir| if (target == enemy +% dir) return true,
            .p => for (getPawnCaptures(enemy_color, enemy)) |capture| if (target == capture) return true,
        }
    }
    return false;
}

fn isVisibleBySlider(self: *const Board, comptime dirs: anytype, src: u8, dest: u8) bool {
    const lut = comptime blk: {
        var l = [1]u8{0} ** 256;
        for (dirs) |dir| {
            for (1..8) |i| {
                l[@as(u8, @truncate(dir *% i))] = dir;
            }
        }
        break :blk l;
    };
    const vector = dest -% src;
    const dir = lut[vector];
    if (dir == 0) return false;
    var t = src +% dir;
    while (t != dest) : (t +%= dir)
        if (!self.board[t].isEmpty())
            return false;
    return true;
}

pub fn calcHashSlow(self: *const Board) Hash {
    var result: Hash = 0;
    for (0..32) |i| {
        const ptype = self.pieces[i];
        const where = self.where[i];
        if (ptype != .none) result ^= zhash.piece(Color.fromId(@intCast(i)), ptype, coord.compress(where));
    }
    result ^= zhash.enpassant(self.state.enpassant);
    result ^= zhash.castle(self.state.castle);
    if (self.active_color == .black) result ^= zhash.move;
    return result;
}

pub fn is50MoveExpired(self: *const Board) bool {
    // TODO: detect if this move is checkmate
    return self.state.no_capture_clock >= 100;
}

pub fn format(self: *const Board, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
    var blanks: u32 = 0;
    for (0..64) |i| {
        const j = (i + (i & 0o70)) ^ 0x70;
        const p = self.board[j];
        if (p.isEmpty()) {
            blanks += 1;
        } else {
            if (blanks != 0) {
                try writer.print("{}", .{blanks});
                blanks = 0;
            }
            try writer.print("{c}", .{p.ptype.toChar(Color.fromId(p.id))});
        }
        if (i % 8 == 7) {
            if (blanks != 0) {
                try writer.print("{}", .{blanks});
                blanks = 0;
            }
            if (i != 63) try writer.print("/", .{});
        }
    }
    try writer.print(" {} ", .{self.active_color});
    try self.state.format(writer, self);
}

pub fn parse(str: []const u8) !Board {
    var it = std.mem.tokenizeAny(u8, str, " \t\r\n");
    const board_str = it.next() orelse return ParseError.InvalidLength;
    const color = it.next() orelse return ParseError.InvalidLength;
    const castling = it.next() orelse return ParseError.InvalidLength;
    const enpassant = it.next() orelse return ParseError.InvalidLength;
    const no_capture_clock = it.next() orelse return ParseError.InvalidLength;
    const ply = it.next() orelse return ParseError.InvalidLength;
    if (it.next() != null) return ParseError.InvalidLength;
    return Board.parseParts(board_str, color, castling, enpassant, no_capture_clock, ply);
}

pub fn parseParts(board_str: []const u8, color_str: []const u8, castle_str: []const u8, enpassant_str: []const u8, no_capture_clock_str: []const u8, ply_str: []const u8) !Board {
    var result = Board.emptyBoard();

    {
        var place_index: u8 = 0;
        var id: [2]u8 = .{ 1, 1 };
        var i: usize = 0;
        while (place_index < 64 and i < board_str.len) : (i += 1) {
            const ch = board_str[i];
            if (ch == '/') continue;
            if (ch >= '1' and ch <= '8') {
                place_index += ch - '0';
                continue;
            }
            const ptype, const color = try PieceType.parse(ch);
            if (ptype == .k) {
                if (result.pieces[color.idBase()] != .none) return ParseError.DuplicateKing;
                result.place(color.idBase(), .k, coord.uncompress(@intCast(place_index)) ^ 0x70);
            } else {
                if (id[@intFromEnum(color)] > 0xf) return ParseError.TooManyPieces;
                const current_id: u5 = @intCast(color.idBase() + id[@intFromEnum(color)]);
                result.place(current_id, ptype, coord.uncompress(@intCast(place_index)) ^ 0x70);
                id[@intFromEnum(color)] += 1;
            }
            place_index += 1;
        }
        if (place_index != 64 or i != board_str.len) return ParseError.InvalidLength;
    }

    if (color_str.len != 1) return ParseError.InvalidLength;
    result.active_color = try Color.parse(color_str[0]);

    result.state = try State.parseParts(result.active_color, castle_str, enpassant_str, no_capture_clock_str, ply_str);

    return result;
}

pub fn debugPrint(self: *const Board, output: anytype) !void {
    for (0..64) |i| {
        const j = (i + (i & 0o70)) ^ 0x70;
        const p = self.board[j];
        try output.print("{c}", .{p.ptype.toChar(Color.fromId(p.id))});
        if (i % 8 == 7) try output.print("\n", .{});
    }
    try output.print("{} ", .{self.active_color});
    try self.state.format(output, self);
    try output.print("\n", .{});
}

pub const Place = packed struct(u8) {
    id: u5,
    ptype: PieceType,

    pub const empty = Place{ .ptype = .none, .id = 0 };
    pub fn isEmpty(self: Place) bool {
        return self.eql(empty);
    }
    pub fn eql(self: Place, other: Place) bool {
        return std.meta.eql(self, other);
    }
};

const Board = @This();
const std = @import("std");
const assert = std.debug.assert;
const getPawnCaptures = @import("common.zig").getPawnCaptures;
const getCastlingRookMove = @import("common.zig").getCastlingRookMove;
const common = @import("common.zig");
const coord = @import("coord.zig");
const zhash = @import("zhash.zig");
const Color = @import("common.zig").Color;
const Hash = @import("zhash.zig").Hash;
const Move = @import("Move.zig");
const MoveCode = @import("MoveCode.zig");
const MoveList = @import("MoveList.zig");
const ParseError = @import("common.zig").ParseError;
const PieceType = @import("common.zig").PieceType;
const State = @import("State.zig");
