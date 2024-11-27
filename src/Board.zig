pieces: [32]PieceType,
where: [32]u8,
board: [128]Place,
state: State,
active_color: Color,
zhistory: [1024]u64,

pub fn emptyBoard() Board {
    return comptime blk: {
        var result: Board = .{
            .pieces = [1]PieceType{.none} ** 32,
            .where = undefined,
            .board = [1]Place{Place.empty} ** 128,
            .state = .{
                .castle = 0,
                .enpassant = 0xff,
                .no_capture_clock = 0,
                .ply = 0,
                .hash = undefined,
            },
            .active_color = .white,
            .zhistory = undefined,
        };
        result.state.hash = result.calcHashSlow();
        result.zhistory[result.state.ply] = result.state.hash;
        break :blk result;
    };
}

pub fn defaultBoard() Board {
    return comptime blk: {
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
        result.zhistory[result.state.ply] = result.state.hash;
        break :blk result;
    };
}

fn place(self: *Board, id: u5, ptype: PieceType, where: u8) void {
    assert(self.board[where] == Place.empty and self.pieces[id] == .none);
    self.pieces[id] = ptype;
    self.where[id] = where;
    self.board[where] = Place{ .ptype = ptype, .id = id };
    self.state.hash ^= zhash.piece(Color.fromId(id), ptype, where);
}

pub fn move(self: *Board, m: Move) State {
    const result = self.state;
    switch (m.mtype) {
        .normal => {
            if (m.isCapture()) {
                assert(self.pieces[m.capture_place.id] == m.capture_place.ptype);
                assert(self.board[m.capture_coord] == m.capture_place);
                self.pieces[m.capture_place.id] = .none;
                self.board[m.capture_coord] = Place.empty;
            }
            assert(self.board[m.src_coord] == Place{ .ptype = m.src_ptype, .id = m.id });
            self.board[m.src_coord] = Place.empty;
            self.board[m.dest_coord] = Place{ .ptype = m.dest_ptype, .id = m.id };
            self.where[m.id] = m.dest_coord;
            self.pieces[m.id] = m.dest_ptype;
        },
        .castle => {
            self.board[m.code.src()] = Place.empty;
            self.board[m.src_coord] = Place.empty;
            self.board[m.code.dest()] = Place{ .ptype = .k, .id = m.id & 0x10 };
            self.board[m.dest_coord] = Place{ .ptype = .r, .id = m.id };
            self.where[m.id & 0x10] = m.code.dest();
            self.where[m.id] = m.dest_coord;
        },
    }
    self.state = m.state;
    self.active_color = self.active_color.invert();
    self.zhistory[m.state.ply] = m.state.hash;
    assert(self.state.hash == self.calcHashSlow());
    return result;
}

pub fn makeMoveByCode(self: *Board, code: MoveCode) bool {
    const p = self.board[code.src()];
    if (p == Place.empty) return false;

    var moves = MoveList{};
    moves.generateMovesForPiece(self, .any, p.id);
    for (moves.moves) |m| {
        if (std.meta.eql(m.code, code)) {
            _ = self.move(m);
            return true;
        }
    }
    return false;
}

pub fn makeMoveByPgnCode(self: *Board, pgn_arg: []const u8) bool {
    if (pgn_arg.len < 2) return false;
    const pgn = switch (pgn_arg[pgn_arg.len - 1]) {
        '#', '+' => pgn_arg[0..pgn_arg.len - 1],
        else => pgn_arg,
    };
    if (pgn.len < 2) return false;

    if (std.mem.eql(u8, pgn, "O-O")) {
        if (self.board[self.active_color.backRank() | 4].ptype != .k) return false;
        switch (self.active_color) {
            .white => return self.makeMoveByCode(MoveCode.parse("e1g1") catch unreachable),
            .black => return self.makeMoveByCode(MoveCode.parse("e8g8") catch unreachable),
        }
    }

    if (std.mem.eql(u8, pgn, "O-O-O")) {
        if (self.board[self.active_color.backRank() | 4].ptype != .k) return false;
        switch (self.active_color) {
            .white => return self.makeMoveByCode(MoveCode.parse("e1c1") catch unreachable),
            .black => return self.makeMoveByCode(MoveCode.parse("e8c8") catch unreachable),
        }
    }

    const dest = coord.fromString(pgn[pgn.len - 2..][0..2].*) catch return false;

    if (pgn.len == 2 or (pgn.len == 3 and pgn[0] == 'P')) {
        for ([2]u8{ 1, 2 }) |i| {
            const delta = switch (self.active_color) {
                .white => 0xF0 *% i,
                .black => 0x10 *% i,
            };
            const src = dest +% delta;
            if (!coord.isValid(src)) return false;
            if (self.board[src].ptype == .p) return self.makeMoveByCode(MoveCode.make(.p, src, .p, dest));
        }
        return false;
    }

    if (pgn.len < 3) return false;

    const is_capture = pgn[pgn.len - 3] == 'x';
    const ptype: PieceType, const expected: u8, const mask: u8 = switch (pgn.len - 2 - @intFromBool(is_capture)) {
        1 => blk: {
            const maybe_ptype = PieceType.parse(pgn[0]) catch null;
            if (maybe_ptype) |pt| break :blk .{ pt[0], 0, 0 };
            const maybe_file: ?u8 = coord.fileFromChar(pgn[0]) catch null;
            if (maybe_file) |file| break :blk .{ .p, file, 0x07 };
            return false;
        },
        2 => blk: {
            const pt = PieceType.parse(pgn[0]) catch return false;
            const maybe_file: ?u8 = coord.fileFromChar(pgn[1]) catch null;
            if (maybe_file) |file| break :blk .{ pt[0], file, 0x07 };
            const maybe_rank: ?u8 = coord.rankFromChar(pgn[1]) catch null;
            if (maybe_rank) |rank| break :blk .{ pt[0], rank, 0x70 };
            return false;
        },
        3 => blk: {
            const pt = PieceType.parse(pgn[0]) catch return false;
            const src = coord.fromString(pgn[1..3].*) catch return false;
            break :blk .{ pt[0], src, 0xFF };
        },
        else => return false,
    };

    const id_base = self.active_color.idBase();
    for (0..32) |id_index| {
        const id: u5 = @truncate(id_base + id_index);
        if (self.pieces[id] != ptype) continue;
        if (self.where[id] & mask != expected) continue;

        var moves = MoveList{};
        moves.generateMovesForPiece(self, .any, id);
        for (moves.moves) |m| {
            if (m.code.dest() == dest) {
                _ = self.move(m);
                return true;
            }
        }
    }
    return false;
}

test {
    var board = Board.defaultBoard();
    const moves = [_][]const u8 {
        "e4", "c5",
        "Nf3", "e6",
        "d4", "cxd4",
        "Nxd4", "Nc6",
        "Nb5", "d6",
        "c4", "Nf6",
        "N1c3", "a6",
        "Na3", "d5",
        "cxd5", "exd5",
        "exd5", "Nb4",
        "Be2", "Bc5",
        "O-O", "O-O",
        "Bf3", "Bf5",
        "Bg5", "Re8",
        "Qd2", "b5",
        "Rad1", "Nd3",
        "Nab1", "h6",
        "Bh4", "b4",
        "Na4", "Bd6",
        "Bg3", "Rc8",
        "b3", "g5",
        "Bxd6", "Qxd6",
        "g3", "Nd7",
        "Bg2", "Qf6",
        "a3", "a5",
        "axb4", "axb4",
        "Qa2", "Bg6",
        "d6", "g4",
        "Qd2", "Kg7",
        "f3", "Qxd6",
        "fxg4", "Qd4+",
        "Kh1", "Nf6",
        "Rf4", "Ne4",
        "Qxd3", "Nf2+",
        "Rxf2", "Bxd3",
        "Rfd2", "Qe3",
        "Rxd3", "Rc1",
        "Nb2", "Qf2",
        "Nd2", "Rxd1+",
        "Nxd1", "Re1+",
    };
    for (moves) |m| {
        try std.testing.expect(board.makeMoveByPgnCode(m));
    }
    var tmp: [50]u8 = undefined;
    const fen = try std.fmt.bufPrint(&tmp, "{}", .{board});
    try std.testing.expectEqualStrings("8/5pk1/7p/8/1p4P1/1P1R2P1/3N1qBP/3Nr2K w - - 1 41", fen);
}

pub fn unmove(self: *Board, m: Move, old_state: State) void {
    switch (m.mtype) {
        .normal => {
            self.board[m.dest_coord] = Place.empty;
            if (m.isCapture()) {
                self.pieces[m.capture_place.id] = m.capture_place.ptype;
                self.board[m.capture_coord] = m.capture_place;
            }
            self.board[m.src_coord] = Place{ .ptype = m.src_ptype, .id = m.id };
            self.where[m.id] = m.src_coord;
            self.pieces[m.id] = m.src_ptype;
        },
        .castle => {
            self.board[m.code.dest()] = Place.empty;
            self.board[m.dest_coord] = Place.empty;
            self.board[m.code.src()] = Place{ .ptype = .k, .id = m.id & 0x10 };
            self.board[m.src_coord] = Place{ .ptype = .r, .id = m.id };
            self.where[m.id & 0x10] = m.code.src();
            self.where[m.id] = m.src_coord;
        },
    }
    self.state = old_state;
    self.active_color = self.active_color.invert();
}

pub fn moveNull(self: *Board) State {
    const result = self.state;
    self.state.hash ^= zhash.move ^ @as(u64, self.state.enpassant) ^ 0xFF;
    self.state.enpassant = 0xFF;
    self.state.no_capture_clock += 1;
    self.state.ply += 1;
    self.active_color = self.active_color.invert();
    self.zhistory[self.state.ply] = self.state.hash;
    assert(self.state.hash == self.calcHashSlow());
    return result;
}

pub fn unmoveNull(self: *Board, old_state: State) void {
    self.state = old_state;
    self.active_color = self.active_color.invert();
}

/// This MUST be checked after making a move on the board.
pub fn isValid(self: *Board) bool {
    // Ensure player that just made a move is not in check!
    const move_color = self.active_color.invert();
    const king_id = move_color.idBase();
    return !self.isAttacked(self.where[king_id], move_color);
}

pub fn isInCheck(self: *Board) bool {
    const king_id = self.active_color.idBase();
    return self.isAttacked(self.where[king_id], self.active_color);
}

pub fn isAttacked(self: *Board, target: u8, friendly: Color) bool {
    const enemy_color = friendly.invert();
    const id_base = enemy_color.idBase();
    for (0..16) |id_index| {
        const id: u5 = @truncate(id_base + id_index);
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

fn isVisibleBySlider(self: *Board, comptime dirs: anytype, src: u8, dest: u8) bool {
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
        if (self.board[t] != Place.empty)
            return false;
    return true;
}

pub fn calcHashSlow(self: *const Board) u64 {
    var result: u64 = 0;
    for (0..32) |i| {
        const ptype = self.pieces[i];
        const where = self.where[i];
        if (ptype != .none) result ^= zhash.piece(Color.fromId(@truncate(i)), ptype, where);
    }
    result ^= self.state.enpassant;
    result ^= zhash.castle(self.state.castle);
    if (self.active_color == .black) result ^= zhash.move;
    return result;
}

pub fn isRepeatedPosition(self: *Board) bool {
    var i: u16 = self.state.ply - self.state.no_capture_clock;
    i += @intFromEnum(self.active_color.invert());
    i &= ~@as(u16, 1);
    i += @intFromEnum(self.active_color);

    while (i + 4 <= self.state.ply) : (i += 2) {
        if (self.zhistory[i] == self.state.hash) {
            return true;
        }
    }
    return false;
}

pub fn is50MoveExpired(self: *Board) bool {
    // TODO: detect if this move is checkmate
    return self.state.no_capture_clock >= 100;
}

pub fn format(self: Board, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
    var blanks: u32 = 0;
    for (0..64) |i| {
        const j = (i + (i & 0o70)) ^ 0x70;
        const p = self.board[j];
        if (p == Place.empty) {
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
    try writer.print(" {} {}", .{ self.active_color, self.state });
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
                result.place(color.idBase(), .k, coord.uncompress(@truncate(place_index)) ^ 0x70);
            } else {
                if (id[@intFromEnum(color)] > 0xf) return ParseError.TooManyPieces;
                const current_id: u5 = @truncate(color.idBase() + id[@intFromEnum(color)]);
                result.place(current_id, ptype, coord.uncompress(@truncate(place_index)) ^ 0x70);
                id[@intFromEnum(color)] += 1;
            }
            place_index += 1;
        }
        if (place_index != 64 or i != board_str.len) return ParseError.InvalidLength;
    }

    if (color_str.len != 1) return ParseError.InvalidLength;
    result.active_color = try Color.parse(color_str[0]);

    result.state = try State.parseParts(result.active_color, castle_str, enpassant_str, no_capture_clock_str, ply_str);
    result.state.hash = result.calcHashSlow();

    return result;
}

pub fn debugPrint(self: *const Board) void {
    for (0..64) |i| {
        const j = (i + (i & 0o70)) ^ 0x70;
        const p = self.board[j];
        std.debug.print("{c}", .{p.ptype.toChar(Color.fromId(p.id))});
        if (i % 8 == 7) std.debug.print("\n", .{});
    }
    std.debug.print("{} {}\n", .{ self.active_color, self.state });
}

pub const Place = packed struct(u8) {
    id: u5,
    ptype: PieceType,

    pub const empty = Place{ .ptype = .none, .id = 0 };
};

const Board = @This();
const std = @import("std");
const assert = std.debug.assert;
const getPawnCaptures = @import("common.zig").getPawnCaptures;
const coord = @import("coord.zig");
const zhash = @import("zhash.zig");
const Color = @import("common.zig").Color;
const Move = @import("Move.zig");
const MoveCode = @import("MoveCode.zig");
const MoveList = @import("MoveList.zig");
const ParseError = @import("common.zig").ParseError;
const PieceType = @import("common.zig").PieceType;
const State = @import("State.zig");
