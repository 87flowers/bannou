const PieceType = enum(u3) {
    none,
    k,
    q,
    r,
    b,
    n,
    p,
};

const Color = enum(u1) {
    white = 0,
    black = 1,
};

pub fn getColor(id: u5) Color {
    return @enumFromInt(id >> 4);
}

/// 0 = white, 1 = black
pub fn toIndex(id: u5) u1 {
    return @intFromEnum(getColor(id));
}

const Place = packed struct {
    ptype: PieceType,
    id: u5,
};

const empty_place = Place{
    .ptype = .none,
    .id = 0,
};

fn stringFromCoord(coord: u8) [2]u8 {
    return .{ 'a' + (coord & 0xF), '1' + (coord >> 4) };
}

fn bitFromCoord(coord: u8) u64 {
    const i = (coord & 7) | ((coord & 0x70) >> 1);
    return @as(u64, 1) << @truncate(i);
}

fn isValidCoord(coord: u8) bool {
    return (coord & 0x88) == 0;
}

const wk_castle_mask = bitFromCoord(0x04) | bitFromCoord(0x07);
const wq_castle_mask = bitFromCoord(0x04) | bitFromCoord(0x00);
const bk_castle_mask = bitFromCoord(0x74) | bitFromCoord(0x77);
const bq_castle_mask = bitFromCoord(0x74) | bitFromCoord(0x70);

const castle_masks = [2][2]u64{
    [2]u64{ wk_castle_mask, wq_castle_mask },
    [2]u64{ bk_castle_mask, bq_castle_mask },
};

const Board = struct {
    bitboard: [2]u64,
    pieces: [32]PieceType,
    where: [32]u8,
    board: [128]Place,
    castle: u64,
    enpassant: u8,
    active_color: Color,
    /// half-moves (for 50 move rule)
    no_capture_clock: u8,
    /// full-moves
    move_number: u8,

    pub fn emptyBoard() Board {
        return .{
            .bitboard = [2]u64{ 0, 0 },
            .pieces = [1]PieceType{.none} ** 32,
            .where = undefined,
            .board = [1]Place{empty_place} ** 128,
            .castle = 0,
            .enpassant = 0xff,
            .active_color = .white,
            .no_capture_clock = 0,
            .move_number = 0,
        };
    }

    pub fn defaultBoard() Board {
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
        return result;
    }

    fn place(self: *Board, id: u5, ptype: PieceType, coord: u8) void {
        assert(self.board[coord].ptype == .none and self.pieces[id] == .none);
        self.pieces[id] = ptype;
        self.where[id] = coord;
        self.board[coord] = Place{ .ptype = ptype, .id = id };
        self.bitboard[toIndex(id)] |= bitFromCoord(coord);
    }

    fn move(self: *Board, ptype: PieceType, id: u5, src: u8, dest: u8) void {
        assert(self.where[id] == src);
        self.board[src] = empty_place;
        const target = &self.board[dest];
        if (target.ptype != .none) {
            assert(self.where[target.id] == dest);
            self.pieces[target.id] = .none;
            self.bitboard[~toIndex(id)] &= ~bitFromCoord(dest);
        }
        self.where[id] = dest;
        self.board[dest] = Place{ .ptype = ptype, .id = id };
        self.bitboard[toIndex(id)] &= ~bitFromCoord(src);
        self.bitboard[toIndex(id)] |= bitFromCoord(dest);
        self.castle[toIndex(id)] |= bitFromCoord(src);
    }

    fn debugPrint(self: *Board) void {
        for (0..64) |i| {
            const j = (i + (i & 0o70)) ^ 0x70;
            const p = self.board[j];
            std.debug.print("{c}", .{@as(u8, switch (p.ptype) {
                .none => '.',
                .k => switch (getColor(p.id)) {
                    .black => 'k',
                    .white => 'K',
                },
                .q => switch (getColor(p.id)) {
                    .black => 'q',
                    .white => 'Q',
                },
                .r => switch (getColor(p.id)) {
                    .black => 'r',
                    .white => 'R',
                },
                .b => switch (getColor(p.id)) {
                    .black => 'b',
                    .white => 'B',
                },
                .n => switch (getColor(p.id)) {
                    .black => 'n',
                    .white => 'N',
                },
                .p => switch (getColor(p.id)) {
                    .black => 'p',
                    .white => 'P',
                },
            })});
            if (i % 8 == 7) std.debug.print("\n", .{});
        }
        // active color
        switch (self.active_color) {
            .white => std.debug.print("w ", .{}),
            .black => std.debug.print("b ", .{}),
        }
        // castling state
        var hasCastle = false;
        if (self.castle & wk_castle_mask == 0) {
            std.debug.print("K", .{});
            hasCastle = true;
        }
        if (self.castle & wq_castle_mask == 0) {
            std.debug.print("Q", .{});
            hasCastle = true;
        }
        if (self.castle & bk_castle_mask == 0) {
            std.debug.print("k", .{});
            hasCastle = true;
        }
        if (self.castle & bq_castle_mask == 0) {
            std.debug.print("q", .{});
            hasCastle = true;
        }
        if (!hasCastle) std.debug.print("-", .{});
        if (isValidCoord(self.enpassant)) {
            std.debug.print(" {s}\n", .{stringFromCoord(self.enpassant)});
        } else {
            std.debug.print(" -\n", .{});
        }
        // move counts
        std.debug.print("{} {}\n", .{ self.no_capture_clock, self.move_number });
    }
};

fn generateSliderMoves(board: *Board, callback: anytype, ptype: PieceType, id: u5, src: u8, dirs: anytype) void {
    for (dirs) |dir| {
        var dest: u8 = src +% dir;
        while (isValidCoord(dest)) : (dest +%= dir) {
            if (board.board[dest].ptype != .none) {
                if (getColor(board.board[dest].id) != board.active_color) {
                    callback(board, ptype, id, src, dest, 0xFF);
                }
                break;
            }
            callback(board, ptype, id, src, dest, 0xFF);
        }
    }
}

fn generateStepperMoves(board: *Board, callback: anytype, ptype: PieceType, id: u5, src: u8, dirs: anytype) void {
    for (dirs) |dir| {
        const dest = src +% dir;
        if (isValidCoord(dest) and (board.board[dest].ptype == .none or getColor(board.board[dest].id) != board.active_color)) {
            callback(board, ptype, id, src, dest, 0xFF);
        }
    }
}

fn generatePawnMovesMayPromote(board: *Board, callback: anytype, isrc: u8, id: u5, src: u8, dest: u8) void {
    if ((isrc & 0xF0) == 0x60) {
        // promotion
        callback(board, .q, id, src, dest, 0xFF);
        callback(board, .r, id, src, dest, 0xFF);
        callback(board, .b, id, src, dest, 0xFF);
        callback(board, .n, id, src, dest, 0xFF);
    } else {
        callback(board, .p, id, src, dest, 0xFF);
    }
}

fn generateLegalMoves(board: *Board, callback: anytype) void {
    const diag_dir = [4]u8{ 0xEF, 0xF1, 0x0F, 0x11 };
    const ortho_dir = [4]u8{ 0xF0, 0xFF, 0x01, 0x10 };
    const all_dir = diag_dir ++ ortho_dir;

    const id_base = @as(u5, @intFromEnum(board.active_color)) << 4;
    for (0..16) |id_index| {
        const id: u5 = @truncate(id_base + id_index);
        const src = board.where[id];
        switch (board.pieces[id]) {
            .none => {},
            .k => generateStepperMoves(board, callback, .k, id, src, all_dir),
            .q => generateSliderMoves(board, callback, .q, id, src, all_dir),
            .r => generateSliderMoves(board, callback, .r, id, src, ortho_dir),
            .b => generateSliderMoves(board, callback, .b, id, src, diag_dir),
            .n => generateStepperMoves(board, callback, .n, id, src, [_]u8{ 0xDF, 0xE1, 0xEE, 0x0E, 0xF2, 0x12, 0x1F, 0x21 }),
            .p => {
                const invert: u8 = @as(u8, @bitCast(-@as(i8, @intFromEnum(board.active_color)))) & 0xF0;
                const isrc = src ^ invert;
                const onestep = (isrc + 0x10) ^ invert;
                const twostep = (isrc + 0x20) ^ invert;
                const captures = [2]u8{ (isrc + 0x0F) ^ invert, (isrc + 0x11) ^ invert };

                if ((isrc & 0xF0) == 0x10 and board.board[onestep].ptype == .none and board.board[twostep].ptype == .none) {
                    callback(board, .p, id, src, twostep, onestep);
                }

                for (captures) |capture| {
                    if (!isValidCoord(capture)) continue;
                    if (capture == board.enpassant or (board.board[capture].ptype != .none and getColor(board.board[capture].id) != board.active_color)) {
                        generatePawnMovesMayPromote(board, callback, isrc, id, src, capture);
                    }
                }

                if (board.board[onestep].ptype == .none) {
                    generatePawnMovesMayPromote(board, callback, isrc, id, src, onestep);
                }
            },
        }
    }
}

pub fn main() !void {
    var board = Board.defaultBoard();
    board.debugPrint();
    generateLegalMoves(&board, struct {
        fn cb(b: *Board, ptype: PieceType, id: u5, src: u8, dest: u8, enpassant: u8) void {
            _ = b;
            _ = id;
            _ = enpassant;
            std.debug.print("{} {s}{s}\n", .{ ptype, stringFromCoord(src), stringFromCoord(dest) });
        }
    }.cb);
}

test "simple test" {}

const std = @import("std");
const assert = std.debug.assert;
