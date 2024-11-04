const PieceType = enum(u3) {
    none,
    k,
    q,
    r,
    b,
    n,
    p,

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
};

const Color = enum(u1) {
    white = 0,
    black = 1,
    pub fn invert(self: Color) Color {
        return @enumFromInt(~@intFromEnum(self));
    }
    pub fn backRank(self: Color) u8 {
        return @as(u8, @bitCast(-@as(i8, @intFromEnum(self)))) & 0x70;
    }
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
    const i = (coord + (coord & 7)) >> 1;
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

const castling_empty_masks = [2][2]u64{
    [2]u64{ bitFromCoord(0x05) | bitFromCoord(0x06), bitFromCoord(0x01) | bitFromCoord(0x02) | bitFromCoord(0x03) },
    [2]u64{ bitFromCoord(0x75) | bitFromCoord(0x76), bitFromCoord(0x71) | bitFromCoord(0x72) | bitFromCoord(0x73) },
};

const State = struct {
    /// bitboard of locations which pieces have been moved from
    castle: u64,
    /// enpassant square coordinate (if invalid then no enpassant square valid)
    enpassant: u8,
    /// for 50 move rule (in half-moves)
    no_capture_clock: u8,
    /// current move number (in half-moves)
    ply: u16,
};

const MoveType = enum {
    normal,
    castle,
};

const Move = struct {
    id: u5,
    src_coord: u8,
    src_ptype: PieceType,
    dest_coord: u8,
    dest_ptype: PieceType,
    capture_coord: u8,
    capture_place: Place,
    state: State,
    mtype: MoveType,

    pub fn debugPrint(self: Move) void {
        switch (self.mtype) {
            .normal => if (self.dest_ptype != self.src_ptype) {
                std.debug.print("{s}{s}{c}", .{stringFromCoord(self.src_coord), stringFromCoord(self.dest_coord), self.dest_ptype.toChar(.black)});
            } else {
                std.debug.print("{s}{s}", .{stringFromCoord(self.src_coord), stringFromCoord(self.dest_coord)});
            },
            .castle => std.debug.print("{s}{s}", .{stringFromCoord(getColor(self.id).backRank() | 4), stringFromCoord(self.capture_coord)}),
        }
    }
};

const MoveList = struct {
    moves: [256]Move = undefined,
    size: u8 = 0,

    pub fn add(self: *MoveList, state: State, ptype: PieceType, id: u5, src: u8, dest: u8) void {
        self.moves[self.size] = .{
            .id = id,
            .src_coord = src,
            .src_ptype = ptype,
            .dest_coord = dest,
            .dest_ptype = ptype,
            .capture_coord = dest,
            .capture_place = empty_place,
            .state = .{
                .castle = state.castle | bitFromCoord(src),
                .enpassant = 0xFF,
                .no_capture_clock = state.no_capture_clock + 1,
                .ply = state.ply + 1,
            },
            .mtype = .normal,
        };
        self.size += 1;
    }

    pub fn addPawnOne(self: *MoveList, state: State, ptype: PieceType, id: u5, src: u8, dest: u8, capture_place: Place) void {
        self.moves[self.size] = .{
            .id = id,
            .src_coord = src,
            .src_ptype = ptype,
            .dest_coord = dest,
            .dest_ptype = ptype,
            .capture_coord = dest,
            .capture_place = capture_place,
            .state = .{
                .castle = state.castle,
                .enpassant = 0xFF,
                .no_capture_clock = 0,
                .ply = state.ply + 1,
            },
            .mtype = .normal,
        };
        self.size += 1;
    }

    pub fn addPawnTwo(self: *MoveList, state: State, ptype: PieceType, id: u5, src: u8, dest: u8, enpassant: u8) void {
        self.moves[self.size] = .{
            .id = id,
            .src_coord = src,
            .src_ptype = ptype,
            .dest_coord = dest,
            .dest_ptype = ptype,
            .capture_coord = dest,
            .capture_place = empty_place,
            .state = .{
                .castle = state.castle,
                .enpassant = enpassant,
                .no_capture_clock = 0,
                .ply = state.ply + 1,
            },
            .mtype = .normal,
        };
        self.size += 1;
    }

    pub fn addPawnPromotion(self: *MoveList, state: State, ptype: PieceType, id: u5, src: u8, dest: u8, capture_place: Place, dest_ptype: PieceType) void {
        self.moves[self.size] = .{
            .id = id,
            .src_coord = src,
            .src_ptype = ptype,
            .dest_coord = dest,
            .dest_ptype = dest_ptype,
            .capture_coord = dest,
            .capture_place = capture_place,
            .state = .{
                .castle = state.castle,
                .enpassant = 0xFF,
                .no_capture_clock = 0,
                .ply = state.ply + 1,
            },
            .mtype = .normal,
        };
        self.size += 1;
    }

    pub fn addCapture(self: *MoveList, state: State, ptype: PieceType, id: u5, src: u8, dest: u8, capture_place: Place) void {
        self.moves[self.size] = .{
            .id = id,
            .src_coord = src,
            .src_ptype = ptype,
            .dest_coord = dest,
            .dest_ptype = ptype,
            .capture_coord = dest,
            .capture_place = capture_place,
            .state = .{
                .castle = state.castle | bitFromCoord(src),
                .enpassant = 0xFF,
                .no_capture_clock = 0,
                .ply = state.ply + 1,
            },
            .mtype = .normal,
        };
        self.size += 1;
    }

    pub fn addEnpassant(self: *MoveList, state: State, ptype: PieceType, id: u5, src: u8, capture_coord: u8, capture_place: Place) void {
        assert(isValidCoord(state.enpassant));
        self.moves[self.size] = .{
            .id = id,
            .src_coord = src,
            .src_ptype = ptype,
            .dest_coord = state.enpassant,
            .dest_ptype = ptype,
            .capture_coord = capture_coord,
            .capture_place = capture_place,
            .state = .{
                .castle = state.castle,
                .enpassant = 0xFF,
                .no_capture_clock = 0,
                .ply = state.ply + 1,
            },
            .mtype = .normal,
        };
        self.size += 1;
    }

    pub fn addCastle(self: *MoveList, state: State, rook_id: u5, src_rook: u8, dest_rook: u8, dest_king: u8) void {
        self.moves[self.size] = .{
            .id = rook_id,
            .src_coord = src_rook,
            .src_ptype = .r,
            .dest_coord = dest_rook,
            .dest_ptype = .r,
            .capture_coord = dest_king,
            .capture_place = empty_place,
            .state = .{
                .castle = state.castle | bitFromCoord(src_rook) | bitFromCoord(getColor(rook_id).backRank() | 4),
                .enpassant = 0xFF,
                .no_capture_clock = 0,
                .ply = state.ply + 1,
            },
            .mtype = .castle,
        };
        self.size += 1;
    }
};

const Board = struct {
    bitboard: [2]u64,
    pieces: [32]PieceType,
    where: [32]u8,
    board: [128]Place,
    state: State,
    active_color: Color,

    pub fn emptyBoard() Board {
        return .{
            .bitboard = [2]u64{ 0, 0 },
            .pieces = [1]PieceType{.none} ** 32,
            .where = undefined,
            .board = [1]Place{empty_place} ** 128,
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

    fn move(self: *Board, m: Move) State {
        const result = self.state;
        switch (m.mtype) {
            .normal => {
                if (m.capture_place != empty_place) {
                    self.pieces[m.capture_place.id] = .none;
                    self.board[m.capture_coord] = empty_place;
                    self.bitboard[~toIndex(m.id)] &= ~bitFromCoord(m.capture_coord);
                }
                self.board[m.src_coord] = empty_place;
                self.board[m.dest_coord] = Place{ .ptype = m.dest_ptype, .id = m.id };
                self.where[m.id] = m.dest_coord;
                self.pieces[m.id] = m.dest_ptype;
                self.bitboard[toIndex(m.id)] &= ~bitFromCoord(m.src_coord);
                self.bitboard[toIndex(m.id)] |= bitFromCoord(m.dest_coord);
            },
            .castle => {
                const king_coord = getColor(m.id).backRank() | 4;
                self.board[king_coord] = empty_place;
                self.board[m.src_coord] = empty_place;
                self.board[m.capture_coord] = Place{ .ptype = .k, .id = m.id & 0x10 };
                self.board[m.dest_coord] = Place{ .ptype = m.dest_ptype, .id = m.id };
                self.where[m.id & 0x10] = m.capture_coord;
                self.where[m.id] = m.dest_coord;
                self.bitboard[toIndex(m.id)] &= ~(bitFromCoord(m.src_coord) | bitFromCoord(king_coord));
                self.bitboard[toIndex(m.id)] |= bitFromCoord(m.dest_coord) | bitFromCoord(m.capture_coord);
            },
        }
        self.state = m.state;
        self.active_color = self.active_color.invert();
        return result;
    }

    fn unmove(self: *Board, m: Move, old_state: State) void {
        switch (m.mtype) {
            .normal => {
                if (m.capture_place != empty_place) {
                    self.pieces[m.capture_place.id] = m.capture_place.ptype;
                    self.board[m.capture_coord] = m.capture_place;
                    self.bitboard[~toIndex(m.id)] |= bitFromCoord(m.capture_coord);
                }
                self.board[m.dest_coord] = empty_place;
                self.board[m.src_coord] = Place{ .ptype = m.src_ptype, .id = m.id };
                self.where[m.id] = m.src_coord;
                self.pieces[m.id] = m.src_ptype;
                self.bitboard[toIndex(m.id)] &= ~bitFromCoord(m.dest_coord);
                self.bitboard[toIndex(m.id)] |= bitFromCoord(m.src_coord);
            },
            .castle => {
                const king_coord = getColor(m.id).backRank() | 4;
                self.board[king_coord] = Place{ .ptype = .k, .id = m.id & 0x10 };
                self.board[m.src_coord] = Place{ .ptype = m.src_ptype, .id = m.id };
                self.board[m.capture_coord] = empty_place;
                self.board[m.dest_coord] = empty_place;
                self.where[m.id & 0x10] = king_coord;
                self.where[m.id] = m.src_coord;
                self.bitboard[toIndex(m.id)] &= ~(bitFromCoord(m.dest_coord) | bitFromCoord(m.capture_coord));
                self.bitboard[toIndex(m.id)] |= bitFromCoord(m.src_coord) | bitFromCoord(king_coord);
            },
        }
        self.state = old_state;
        self.active_color = self.active_color.invert();
    }

    fn debugPrint(self: *Board) void {
        for (0..64) |i| {
            const j = (i + (i & 0o70)) ^ 0x70;
            const p = self.board[j];
            std.debug.print("{c}", .{p.ptype.toChar(getColor(p.id))});
            if (i % 8 == 7) std.debug.print("\n", .{});
        }
        // active color
        switch (self.active_color) {
            .white => std.debug.print("w ", .{}),
            .black => std.debug.print("b ", .{}),
        }
        // castling state
        var hasCastle = false;
        if (self.state.castle & wk_castle_mask == 0) {
            std.debug.print("K", .{});
            hasCastle = true;
        }
        if (self.state.castle & wq_castle_mask == 0) {
            std.debug.print("Q", .{});
            hasCastle = true;
        }
        if (self.state.castle & bk_castle_mask == 0) {
            std.debug.print("k", .{});
            hasCastle = true;
        }
        if (self.state.castle & bq_castle_mask == 0) {
            std.debug.print("q", .{});
            hasCastle = true;
        }
        if (!hasCastle) std.debug.print("-", .{});
        if (isValidCoord(self.state.enpassant)) {
            std.debug.print(" {s}\n", .{stringFromCoord(self.state.enpassant)});
        } else {
            std.debug.print(" -\n", .{});
        }
        // move counts
        std.debug.print("{} {}\n", .{ self.state.no_capture_clock, self.state.ply });
    }
};

fn generateSliderMoves(board: *Board, moves: *MoveList, ptype: PieceType, id: u5, src: u8, dirs: anytype) void {
    for (dirs) |dir| {
        var dest: u8 = src +% dir;
        while (isValidCoord(dest)) : (dest +%= dir) {
            if (board.board[dest].ptype != .none) {
                if (getColor(board.board[dest].id) != board.active_color) {
                    moves.addCapture(board.state, ptype, id, src, dest, board.board[dest]);
                }
                break;
            }
            moves.add(board.state, ptype, id, src, dest);
        }
    }
}

fn generateStepperMoves(board: *Board, moves: *MoveList, ptype: PieceType, id: u5, src: u8, dirs: anytype) void {
    for (dirs) |dir| {
        const dest = src +% dir;
        if (isValidCoord(dest)) {
            if (board.board[dest].ptype == .none) {
                moves.add(board.state, ptype, id, src, dest);
            } else if (getColor(board.board[dest].id) != board.active_color) {
                moves.addCapture(board.state, ptype, id, src, dest, board.board[dest]);
            }
        }
    }
}

fn generatePawnMovesMayPromote(board: *Board, moves: *MoveList, isrc: u8, id: u5, src: u8, dest: u8) void {
    if ((isrc & 0xF0) == 0x60) {
        // promotion
        moves.addPawnPromotion(board.state, .p, id, src, dest, board.board[dest], .q);
        moves.addPawnPromotion(board.state, .p, id, src, dest, board.board[dest], .r);
        moves.addPawnPromotion(board.state, .p, id, src, dest, board.board[dest], .b);
        moves.addPawnPromotion(board.state, .p, id, src, dest, board.board[dest], .n);
    } else {
        moves.addPawnOne(board.state, .p, id, src, dest, board.board[dest]);
    }
}

fn generateMoves(board: *Board, moves: *MoveList) void {
    const diag_dir = [4]u8{ 0xEF, 0xF1, 0x0F, 0x11 };
    const ortho_dir = [4]u8{ 0xF0, 0xFF, 0x01, 0x10 };
    const all_dir = diag_dir ++ ortho_dir;

    const id_base = @as(u5, @intFromEnum(board.active_color)) << 4;
    for (0..16) |id_index| {
        const id: u5 = @truncate(id_base + id_index);
        const src = board.where[id];
        switch (board.pieces[id]) {
            .none => {},
            .k => {
                generateStepperMoves(board, moves, .k, id, src, all_dir);

                const castle_k, const castle_q = castle_masks[@intFromEnum(board.active_color)];
                const empty_k, const empty_q = castling_empty_masks[@intFromEnum(board.active_color)];
                const rank: u8 = board.active_color.backRank();
                if (castle_k & board.state.castle == 0 and (board.bitboard[0] | board.bitboard[1]) & empty_k == 0) {
                    moves.addCastle(board.state, board.board[rank | 7].id, rank | 7, rank | 4, rank | 6);
                }
                if (castle_q & board.state.castle == 0 and (board.bitboard[0] | board.bitboard[1]) & empty_q == 0) {
                    moves.addCastle(board.state, board.board[rank | 0].id, rank | 0, rank | 3, rank | 2);
                }
            },
            .q => generateSliderMoves(board, moves, .q, id, src, all_dir),
            .r => generateSliderMoves(board, moves, .r, id, src, ortho_dir),
            .b => generateSliderMoves(board, moves, .b, id, src, diag_dir),
            .n => generateStepperMoves(board, moves, .n, id, src, [_]u8{ 0xDF, 0xE1, 0xEE, 0x0E, 0xF2, 0x12, 0x1F, 0x21 }),
            .p => {
                const invert: u8 = @as(u8, @bitCast(-@as(i8, @intFromEnum(board.active_color)))) & 0x70;
                const isrc = src ^ invert;
                const onestep = (isrc + 0x10) ^ invert;
                const twostep = (isrc + 0x20) ^ invert;
                const captures = [2]u8{ (isrc + 0x0F) ^ invert, (isrc + 0x11) ^ invert };

                if ((isrc & 0xF0) == 0x10 and board.board[onestep].ptype == .none and board.board[twostep].ptype == .none) {
                    moves.addPawnTwo(board.state, .p, id, src, twostep, onestep);
                }

                for (captures) |capture| {
                    if (!isValidCoord(capture)) continue;
                    if (capture == board.state.enpassant) {
                        const capture_coord = ((capture ^ invert) + 0x10) ^ invert;
                        moves.addEnpassant(board.state, .p, id, src, capture_coord, board.board[capture_coord]);
                    } else if (board.board[capture].ptype != .none and getColor(board.board[capture].id) != board.active_color) {
                        generatePawnMovesMayPromote(board, moves, isrc, id, src, capture);
                    }
                }

                if (board.board[onestep].ptype == .none) {
                    generatePawnMovesMayPromote(board, moves, isrc, id, src, onestep);
                }
            },
        }
    }
}

pub fn perft(board: *Board, depth: usize) usize {
    if (depth == 0) return 1;
    var result: usize = 0;
    var moves = MoveList{};
    generateMoves(board, &moves);
    for (0..moves.size) |i| {
        const m = moves.moves[i];
        const old_state = board.move(m);
        // m.debugPrint();
        // std.debug.print("\n", .{});
        // board.debugPrint();
        result += perft(board, depth - 1);
        board.unmove(m, old_state);
    }
    return result;
}

pub fn main() !void {
    var board = Board.defaultBoard();
    for (0..5) |i| {
        const p = perft(&board, i);
        std.debug.print("perft({}) = {}\n", .{i, p});
    }
}

test "simple test" {}

const std = @import("std");
const assert = std.debug.assert;
