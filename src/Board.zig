pieces: [32]PieceType,
where: [32]u8,
board: [128]Place,
state: State,
active_color: Color,
zhistory: [common.max_game_ply]u64,

pub fn copyFrom(self: *Board, other: *const Board) void {
    self.pieces = other.pieces;
    self.where = other.where;
    self.board = other.board;
    self.state = other.state;
    self.active_color = other.active_color;
    const zhistory_len = other.state.ply + 1;
    @memcpy(self.zhistory[0..zhistory_len], other.zhistory[0..zhistory_len]);
}

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

pub fn place(self: *Board, id: u5, ptype: PieceType, where: u8) void {
    assert(self.board[where] == Place.empty and self.pieces[id] == .none);
    self.pieces[id] = ptype;
    self.where[id] = where;
    self.board[where] = Place{ .ptype = ptype, .id = id };
    self.state.hash ^= zhash.piece(Color.fromId(id), ptype, where);
    self.zhistory[self.state.ply] = self.state.hash;
}

pub fn unplace(self: *Board, id: u5) void {
    assert(self.pieces[id] != .none and self.board[self.where[id]] != Place.empty);
    const ptype = self.pieces[id];
    const where = self.where[id];
    self.state.hash ^= zhash.piece(Color.fromId(id), ptype, where);
    self.zhistory[self.state.ply] = self.state.hash;
    self.pieces[id] = .none;
    self.where[id] = 0xFF;
    self.board[where] = Place.empty;
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
    for (0..moves.size) |i| {
        const m = moves.moves[i];
        if (std.meta.eql(m.code, code)) {
            _ = self.move(m);
            return true;
        }
    }
    return false;
}

pub fn makeMoveByPgnCode(self: *Board, pgn_arg: []const u8) bool {
    if (pgn_arg.len < 2) return false;
    var pgn = switch (pgn_arg[pgn_arg.len - 1]) {
        '#', '+' => pgn_arg[0 .. pgn_arg.len - 1],
        else => pgn_arg,
    };

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

    var promotion_ptype: PieceType = .none;
    if (pgn.len >= 4 and pgn[pgn.len - 2] == '=') {
        promotion_ptype = PieceType.parseUncolored(pgn[pgn.len - 1]) catch return false;
        pgn = pgn[0 .. pgn.len - 2];
    }

    if (pgn.len < 2) return false;
    const is_capture = pgn.len >= 3 and pgn[pgn.len - 3] == 'x';
    const dest: u8 = coord.fromString(pgn[pgn.len - 2 ..][0..2].*) catch return false;

    var src_ptype: PieceType = .none;
    var src: u8 = 0;
    var src_mask: u8 = 0;
    switch (pgn.len - @intFromBool(is_capture)) {
        2 => {
            // e.g. e4
            if (is_capture) return false;
            src_ptype = .p;
        },
        3 => {
            if (pgn[0] >= 'a' and pgn[0] <= 'h') {
                // e.g. axb3
                if (!is_capture) return false;
                src_ptype = .p;
                src = coord.fileFromChar(pgn[0]) catch unreachable;
                src_mask = 0x07;
            } else {
                // e.g. Bb3, Bxb3
                src_ptype = PieceType.parseUncolored(pgn[0]) catch return false;
            }
        },
        4 => {
            // e.g. Qhxa3, Q3xb7, Qba4, Q6a3
            src_ptype = PieceType.parseUncolored(pgn[0]) catch return false;
            if (coord.fileFromChar(pgn[1]) catch null) |file| {
                src = file;
                src_mask = 0x07;
            } else if (coord.rankFromChar(pgn[1]) catch null) |rank| {
                src = rank;
                src_mask = 0x70;
            } else {
                return false;
            }
        },
        5 => {
            // e.g. Qa1b2, Qa1xb2
            src_ptype = PieceType.parseUncolored(pgn[0]) catch return false;
            src = coord.fromString(pgn[1..3].*) catch return false;
            src_mask = 0xFF;
        },
        else => return false,
    }

    var candidate: ?Move = null;
    const id_base = self.active_color.idBase();
    for (0..16) |id_index| {
        const id: u5 = @truncate(id_base + id_index);
        if (self.pieces[id] != src_ptype) continue;
        if (self.where[id] & src_mask != src) continue;

        var moves = MoveList{};
        moves.generateMovesForPiece(self, .any, id);
        for (0..moves.size) |i| {
            const m = moves.moves[i];
            if (m.isCapture() == is_capture and m.code.dest() == dest and m.code.promotion() == promotion_ptype) {
                const old_state = self.move(m);
                defer self.unmove(m, old_state);
                if (!self.isValid()) continue;
                if (candidate != null) return false;
                candidate = m;
            }
        }
    }
    if (candidate) |m| {
        _ = self.move(m);
        return true;
    }
    return false;
}

test {
    var board = Board.defaultBoard();
    const moves = [_][]const u8{
        "e4",   "c5",
        "Nf3",  "e6",
        "d4",   "cxd4",
        "Nxd4", "Nc6",
        "Nb5",  "d6",
        "c4",   "Nf6",
        "N1c3", "a6",
        "Na3",  "d5",
        "cxd5", "exd5",
        "exd5", "Nb4",
        "Be2",  "Bc5",
        "O-O",  "O-O",
        "Bf3",  "Bf5",
        "Bg5",  "Re8",
        "Qd2",  "b5",
        "Rad1", "Nd3",
        "Nab1", "h6",
        "Bh4",  "b4",
        "Na4",  "Bd6",
        "Bg3",  "Rc8",
        "b3",   "g5",
        "Bxd6", "Qxd6",
        "g3",   "Nd7",
        "Bg2",  "Qf6",
        "a3",   "a5",
        "axb4", "axb4",
        "Qa2",  "Bg6",
        "d6",   "g4",
        "Qd2",  "Kg7",
        "f3",   "Qxd6",
        "fxg4", "Qd4+",
        "Kh1",  "Nf6",
        "Rf4",  "Ne4",
        "Qxd3", "Nf2+",
        "Rxf2", "Bxd3",
        "Rfd2", "Qe3",
        "Rxd3", "Rc1",
        "Nb2",  "Qf2",
        "Nd2",  "Rxd1+",
        "Nxd1", "Re1+",
    };
    for (moves) |m| {
        try std.testing.expect(board.makeMoveByPgnCode(m));
    }
    var tmp: [50]u8 = undefined;
    const fen = try std.fmt.bufPrint(&tmp, "{}", .{board});
    try std.testing.expectEqualStrings("8/5pk1/7p/8/1p4P1/1P1R2P1/3N1qBP/3Nr2K w - - 1 41", fen);
}

test {
    const cases = [_]struct { []const u8, []const u8, []const u8 }{
        .{ "7r/3r1p1p/6p1/1p6/2B5/5PP1/1Q5P/1K1k4 b - - 0 38", "bxc4", "7r/3r1p1p/6p1/8/2p5/5PP1/1Q5P/1K1k4 w - - 0 39" },
        .{ "2n1r1n1/1p1k1p2/6pp/R2pP3/3P4/8/5PPP/2R3K1 b - - 0 30", "Nge7", "2n1r3/1p1knp2/6pp/R2pP3/3P4/8/5PPP/2R3K1 w - - 1 31" },
        .{ "8/5p2/1kn1r1n1/1p1pP3/6K1/8/4R3/5R2 b - - 9 60", "Ngxe5+", "8/5p2/1kn1r3/1p1pn3/6K1/8/4R3/5R2 w - - 0 61" },
        .{ "r3k2r/pp1bnpbp/1q3np1/3p4/3N1P2/1PP1Q2P/P1B3P1/RNB1K2R b KQkq - 5 15", "Ng8", "r3k1nr/pp1bnpbp/1q4p1/3p4/3N1P2/1PP1Q2P/P1B3P1/RNB1K2R w KQkq - 6 16" },
    };
    for (cases) |case| {
        const before, const pgncode, const after = case;
        var board = try Board.parse(before);
        try std.testing.expect(board.makeMoveByPgnCode(pgncode));
        var tmp: [128]u8 = undefined;
        const fen = try std.fmt.bufPrint(&tmp, "{}", .{board});
        try std.testing.expectEqualStrings(after, fen);
    }
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

pub fn format(self: *const Board, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
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

pub fn debugPrint(self: *const Board, output: anytype) !void {
    for (0..64) |i| {
        const j = (i + (i & 0o70)) ^ 0x70;
        const p = self.board[j];
        try output.print("{c}", .{p.ptype.toChar(Color.fromId(p.id))});
        if (i % 8 == 7) std.debug.print("\n", .{});
    }
    try output.print("{} ", .{self.active_color});
    try self.state.format(output, self);
    try output.print("\n", .{});
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
const common = @import("common.zig");
const coord = @import("coord.zig");
const zhash = @import("zhash.zig");
const Color = @import("common.zig").Color;
const Move = @import("Move.zig");
const MoveCode = @import("MoveCode.zig");
const MoveList = @import("MoveList.zig");
const ParseError = @import("common.zig").ParseError;
const PieceType = @import("common.zig").PieceType;
const State = @import("State.zig");
