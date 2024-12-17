moves: [common.max_legal_moves]Move = undefined,
size: u8 = 0,

pub const MoveGeneratorMode = enum {
    any,
    captures_only,
};

pub fn generateMoves(self: *MoveList, board: *Board, comptime mode: MoveGeneratorMode) void {
    const id_base = board.active_color.idBase();
    for (0..16) |id_index| {
        const id: u5 = @truncate(id_base + id_index);
        self.generateMovesForPiece(board, mode, id);
    }
}

pub fn generateMovesForPiece(self: *MoveList, board: *Board, comptime mode: MoveGeneratorMode, id: u5) void {
    const src = board.where[id];
    switch (board.pieces[id]) {
        .none => {},
        .k => {
            self.generateStepperMoves(board, mode, .k, id, src, coord.all_dir);

            const rank: u8 = board.active_color.backRank();
            if (board.where[id] == rank | 4) {
                const castle_masks = [2][2]u64{
                    [2]u64{ castle_mask.wk, castle_mask.wq },
                    [2]u64{ castle_mask.bk, castle_mask.bq },
                };
                const castle_k, const castle_q = castle_masks[@intFromEnum(board.active_color)];
                if (castle_k & board.state.castle == 0 and board.board[rank | 5] == Place.empty and board.board[rank | 6] == Place.empty) {
                    if (!board.isAttacked(rank | 4, board.active_color) and !board.isAttacked(rank | 5, board.active_color) and !board.isAttacked(rank | 6, board.active_color)) {
                        if (board.board[rank | 7].ptype == .r and Color.fromId(board.board[rank | 7].id) == board.active_color) {
                            self.addCastle(mode, board.state, board.board[rank | 7].id, rank | 7, rank | 5, rank | 4, rank | 6);
                        }
                    }
                }
                if (castle_q & board.state.castle == 0 and board.board[rank | 1] == Place.empty and board.board[rank | 2] == Place.empty and board.board[rank | 3] == Place.empty) {
                    if (!board.isAttacked(rank | 2, board.active_color) and !board.isAttacked(rank | 3, board.active_color) and !board.isAttacked(rank | 4, board.active_color)) {
                        if (board.board[rank | 0].ptype == .r and Color.fromId(board.board[rank | 0].id) == board.active_color) {
                            self.addCastle(mode, board.state, board.board[rank | 0].id, rank | 0, rank | 3, rank | 4, rank | 2);
                        }
                    }
                }
            }
        },
        .q => self.generateSliderMoves(board, mode, .q, id, src, coord.all_dir),
        .r => self.generateSliderMoves(board, mode, .r, id, src, coord.ortho_dir),
        .b => self.generateSliderMoves(board, mode, .b, id, src, coord.diag_dir),
        .n => self.generateStepperMoves(board, mode, .n, id, src, coord.knight_dir),
        .p => {
            const invert = board.active_color.toRankInvertMask();
            const isrc = src ^ invert;
            const onestep = (isrc + 0x10) ^ invert;
            const twostep = (isrc + 0x20) ^ invert;
            const captures = getPawnCaptures(board.active_color, src);

            if ((isrc & 0xF0) == 0x10 and board.board[onestep].ptype == .none and board.board[twostep].ptype == .none) {
                self.addPawnTwo(mode, board.state, .p, id, src, twostep, onestep);
            }

            for (captures) |capture| {
                if (!coord.isValid(capture)) continue;
                if (capture == board.state.enpassant) {
                    const capture_coord = ((capture ^ invert) - 0x10) ^ invert;
                    self.addEnpassant(mode, board.state, .p, id, src, capture_coord, board.board[capture_coord]);
                } else if (board.board[capture].ptype != .none and Color.fromId(board.board[capture].id) != board.active_color) {
                    self.generatePawnMovesMayPromote(board, mode, isrc, id, src, capture, .capture);
                }
            }

            if (board.board[onestep].ptype == .none) {
                self.generatePawnMovesMayPromote(board, mode, isrc, id, src, onestep, .no_capture);
            }
        },
    }
}

pub fn sortInOrder(self: *MoveList, order: []i32) void {
    const Context = struct {
        ml: *MoveList,
        order: []i32,

        pub fn lessThan(ctx: @This(), a: usize, b: usize) bool {
            return ctx.order[a] > ctx.order[b];
        }

        pub fn swap(ctx: @This(), a: usize, b: usize) void {
            std.mem.swap(Move, &ctx.ml.moves[a], &ctx.ml.moves[b]);
            std.mem.swap(i32, &ctx.order[a], &ctx.order[b]);
        }
    };
    std.sort.heapContext(0, self.size, Context{ .ml = self, .order = order });
}

fn generateSliderMoves(self: *MoveList, board: *Board, comptime mode: MoveGeneratorMode, ptype: PieceType, id: u5, src: u8, dirs: anytype) void {
    assert(board.where[id] == src and board.board[src] == Place{ .ptype = ptype, .id = id });
    for (dirs) |dir| {
        var dest: u8 = src +% dir;
        while (coord.isValid(dest)) : (dest +%= dir) {
            if (board.board[dest].ptype != .none) {
                if (Color.fromId(board.board[dest].id) != board.active_color) {
                    self.addCapture(mode, board.state, ptype, id, src, dest, board.board[dest]);
                }
                break;
            }
            self.add(mode, board.state, ptype, id, src, dest);
        }
    }
}

fn generateStepperMoves(self: *MoveList, board: *Board, comptime mode: MoveGeneratorMode, ptype: PieceType, id: u5, src: u8, dirs: anytype) void {
    assert(board.where[id] == src and board.board[src] == Place{ .ptype = ptype, .id = id });
    for (dirs) |dir| {
        const dest = src +% dir;
        if (coord.isValid(dest)) {
            if (board.board[dest].ptype == .none) {
                self.add(mode, board.state, ptype, id, src, dest);
            } else if (Color.fromId(board.board[dest].id) != board.active_color) {
                self.addCapture(mode, board.state, ptype, id, src, dest, board.board[dest]);
            }
        }
    }
}

fn generatePawnMovesMayPromote(self: *MoveList, board: *Board, comptime mode: MoveGeneratorMode, isrc: u8, id: u5, src: u8, dest: u8, comptime has_capture: MoveList.HasCapture) void {
    assert(board.where[id] == src and board.board[src] == Place{ .ptype = .p, .id = id });
    if ((isrc & 0xF0) == 0x60) {
        // promotion
        self.addPawnPromotion(mode, board.state, .p, id, src, dest, board.board[dest], .q, has_capture);
        self.addPawnPromotion(mode, board.state, .p, id, src, dest, board.board[dest], .r, has_capture);
        self.addPawnPromotion(mode, board.state, .p, id, src, dest, board.board[dest], .b, has_capture);
        self.addPawnPromotion(mode, board.state, .p, id, src, dest, board.board[dest], .n, has_capture);
    } else {
        self.addPawnOne(mode, board.state, .p, id, src, dest, board.board[dest], has_capture);
    }
}

fn add(self: *MoveList, comptime mode: MoveGeneratorMode, state: State, ptype: PieceType, id: u5, src: u8, dest: u8) void {
    if (mode == .captures_only) return;
    self.moves[self.size] = .{
        .code = MoveCode.make(ptype, src, ptype, dest),
        .id = id,
        .src_coord = src,
        .src_ptype = ptype,
        .dest_coord = dest,
        .dest_ptype = ptype,
        .capture_coord = dest,
        .capture_place = Place.empty,
        .state = .{
            .castle = state.castle | coord.toBit(src),
            .enpassant = 0xFF,
            .no_capture_clock = state.no_capture_clock + 1,
            .ply = state.ply + 1,
            .hash = state.hash ^
                zhash.move ^
                zhash.piece(Color.fromId(id), ptype, src) ^
                zhash.piece(Color.fromId(id), ptype, dest) ^
                state.enpassant ^
                0xFF ^
                zhash.castle(state.castle) ^
                zhash.castle((state.castle | coord.toBit(src))),
        },
        .mtype = .normal,
    };
    self.size += 1;
}

fn addPawnOne(self: *MoveList, comptime mode: MoveGeneratorMode, state: State, ptype: PieceType, id: u5, src: u8, dest: u8, capture_place: Place, comptime has_capture: HasCapture) void {
    assert((has_capture == .capture) != (capture_place == Place.empty));
    if (mode == .captures_only and has_capture != .capture) return;
    self.moves[self.size] = .{
        .code = MoveCode.make(ptype, src, ptype, dest),
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
            .hash = state.hash ^
                zhash.move ^
                zhash.piece(Color.fromId(id), ptype, src) ^
                zhash.piece(Color.fromId(id), ptype, dest) ^
                switch (has_capture) {
                    .capture => zhash.piece(Color.fromId(id).invert(), capture_place.ptype, dest),
                    .no_capture => 0,
                } ^
                state.enpassant ^
                0xFF,
        },
        .mtype = .normal,
    };
    self.size += 1;
}

fn addPawnTwo(self: *MoveList, comptime mode: MoveGeneratorMode, state: State, ptype: PieceType, id: u5, src: u8, dest: u8, enpassant: u8) void {
    if (mode == .captures_only) return;
    self.moves[self.size] = .{
        .code = MoveCode.make(ptype, src, ptype, dest),
        .id = id,
        .src_coord = src,
        .src_ptype = ptype,
        .dest_coord = dest,
        .dest_ptype = ptype,
        .capture_coord = dest,
        .capture_place = Place.empty,
        .state = .{
            .castle = state.castle,
            .enpassant = enpassant,
            .no_capture_clock = 0,
            .ply = state.ply + 1,
            .hash = state.hash ^
                zhash.move ^
                zhash.piece(Color.fromId(id), ptype, src) ^
                zhash.piece(Color.fromId(id), ptype, dest) ^
                state.enpassant ^
                enpassant,
        },
        .mtype = .normal,
    };
    self.size += 1;
}

fn addPawnPromotion(self: *MoveList, comptime mode: MoveGeneratorMode, state: State, src_ptype: PieceType, id: u5, src: u8, dest: u8, capture_place: Place, dest_ptype: PieceType, comptime has_capture: HasCapture) void {
    assert((has_capture == .capture) != (capture_place == Place.empty));
    if (mode == .captures_only and has_capture != .capture) return;
    self.moves[self.size] = .{
        .code = MoveCode.make(src_ptype, src, dest_ptype, dest),
        .id = id,
        .src_coord = src,
        .src_ptype = src_ptype,
        .dest_coord = dest,
        .dest_ptype = dest_ptype,
        .capture_coord = dest,
        .capture_place = capture_place,
        .state = .{
            .castle = state.castle | coord.toBit(dest),
            .enpassant = 0xFF,
            .no_capture_clock = 0,
            .ply = state.ply + 1,
            .hash = state.hash ^
                zhash.move ^
                zhash.piece(Color.fromId(id), src_ptype, src) ^
                zhash.piece(Color.fromId(id), dest_ptype, dest) ^
                switch (has_capture) {
                    .capture => zhash.piece(Color.fromId(id).invert(), capture_place.ptype, dest),
                    .no_capture => 0,
                } ^
                state.enpassant ^
                0xFF ^
                zhash.castle(state.castle) ^
                zhash.castle((state.castle | coord.toBit(dest))),
        },
        .mtype = .normal,
    };
    self.size += 1;
}

fn addCapture(self: *MoveList, comptime mode: MoveGeneratorMode, state: State, ptype: PieceType, id: u5, src: u8, dest: u8, capture_place: Place) void {
    assert(Color.fromId(id).invert() == Color.fromId(capture_place.id));
    _ = mode;
    self.moves[self.size] = .{
        .code = MoveCode.make(ptype, src, ptype, dest),
        .id = id,
        .src_coord = src,
        .src_ptype = ptype,
        .dest_coord = dest,
        .dest_ptype = ptype,
        .capture_coord = dest,
        .capture_place = capture_place,
        .state = .{
            .castle = state.castle | coord.toBit(src) | coord.toBit(dest),
            .enpassant = 0xFF,
            .no_capture_clock = 0,
            .ply = state.ply + 1,
            .hash = state.hash ^
                zhash.move ^
                zhash.piece(Color.fromId(id), ptype, src) ^
                zhash.piece(Color.fromId(id), ptype, dest) ^
                zhash.piece(Color.fromId(id).invert(), capture_place.ptype, dest) ^
                state.enpassant ^
                0xFF ^
                zhash.castle(state.castle) ^
                zhash.castle((state.castle | coord.toBit(src) | coord.toBit(dest))),
        },
        .mtype = .normal,
    };
    self.size += 1;
}

fn addEnpassant(self: *MoveList, comptime mode: MoveGeneratorMode, state: State, ptype: PieceType, id: u5, src: u8, capture_coord: u8, capture_place: Place) void {
    assert(coord.isValid(state.enpassant));
    assert(Color.fromId(id).invert() == Color.fromId(capture_place.id));
    _ = mode;
    self.moves[self.size] = .{
        .code = MoveCode.make(ptype, src, ptype, state.enpassant),
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
            .hash = state.hash ^
                zhash.move ^
                zhash.piece(Color.fromId(id), ptype, src) ^
                zhash.piece(Color.fromId(id), ptype, state.enpassant) ^
                zhash.piece(Color.fromId(id).invert(), capture_place.ptype, capture_coord) ^
                state.enpassant ^
                0xFF,
        },
        .mtype = .normal,
    };
    self.size += 1;
}

fn addCastle(self: *MoveList, comptime mode: MoveGeneratorMode, state: State, rook_id: u5, src_rook: u8, dest_rook: u8, src_king: u8, dest_king: u8) void {
    if (mode == .captures_only) return;
    self.moves[self.size] = .{
        .code = MoveCode.make(.k, src_king, .k, dest_king),
        .id = rook_id,
        .src_coord = src_rook,
        .src_ptype = .r,
        .dest_coord = dest_rook,
        .dest_ptype = .r,
        .capture_coord = dest_rook,
        .capture_place = Place.empty,
        .state = .{
            .castle = state.castle | coord.toBit(src_rook) | coord.toBit(src_king),
            .enpassant = 0xFF,
            .no_capture_clock = state.no_capture_clock + 1,
            .ply = state.ply + 1,
            .hash = state.hash ^
                zhash.move ^
                zhash.piece(Color.fromId(rook_id), .k, src_king) ^
                zhash.piece(Color.fromId(rook_id), .k, dest_king) ^
                zhash.piece(Color.fromId(rook_id), .r, src_rook) ^
                zhash.piece(Color.fromId(rook_id), .r, dest_rook) ^
                state.enpassant ^
                0xFF ^
                zhash.castle(state.castle) ^
                zhash.castle((state.castle | coord.toBit(src_rook) | coord.toBit(src_king))),
        },
        .mtype = .castle,
    };
    self.size += 1;
}

const HasCapture = enum { capture, no_capture };

const MoveList = @This();
const std = @import("std");
const assert = std.debug.assert;
const castle_mask = @import("castle_mask.zig");
const common = @import("common.zig");
const coord = @import("coord.zig");
const getPawnCaptures = @import("common.zig").getPawnCaptures;
const zhash = @import("zhash.zig");
const Board = @import("Board.zig");
const Color = @import("common.zig").Color;
const Move = @import("Move.zig");
const MoveCode = @import("MoveCode.zig");
const PieceType = @import("common.zig").PieceType;
const Place = @import("Board.zig").Place;
const State = @import("State.zig");
