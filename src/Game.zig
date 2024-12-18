const tt_size = 0x1000000;
const max_history_value: i32 = 1 << 24;

board: Board,
tt: [tt_size]TTEntry,
killers: [common.max_search_ply]MoveCode,
history: [6 * 64 * 64]i32,

pub fn reset(self: *Game) void {
    self.board = Board.defaultBoard();
    @memset(&self.tt, TTEntry.empty);
    @memset(&self.killers, MoveCode.none);
    @memset(&self.history, 0);
}

pub fn ttLoad(self: *Game) TTEntry {
    return self.tt[self.board.state.hash % tt_size];
}

pub fn ttStore(self: *Game, tte: TTEntry) void {
    self.tt[self.board.state.hash % tt_size] = tte;
}

pub fn sortMoves(self: *Game, moves: *MoveList, tt_move: MoveCode, ply: u32) void {
    const killer = self.getKiller(ply);

    var sort_scores: [common.max_legal_moves]i32 = undefined;
    for (0..moves.size) |i| {
        const m = moves.moves[i];
        sort_scores[i] = blk: {
            if (m.code.code == tt_move.code)
                break :blk @as(i32, 127 << 24);
            if (m.isCapture())
                break :blk @as(i32, 125 << 24) + (@as(i32, @intFromEnum(m.capture_place.ptype)) << 8) - @intFromEnum(m.src_ptype);
            if (m.isPromotion() and m.dest_ptype == .q)
                break :blk @as(i32, 124 << 24);
            if (m.code.code == killer.code)
                break :blk @as(i32, 123 << 24);
            break :blk self.getHistory(m).*;
        };
    }
    moves.sortInOrder(&sort_scores);
}

fn getKiller(self: *Game, ply: u32) MoveCode {
    return self.killers[ply];
}

fn updateKiller(self: *Game, ply: u32, m: Move) void {
    self.killers[ply] = m.code;
}

fn getHistory(self: *Game, m: Move) *i32 {
    const ptype: usize = @intFromEnum(m.dest_ptype) - 1;
    const src: usize = coord.compress(m.src_coord);
    const dest: usize = coord.compress(m.dest_coord);
    return &self.history[ptype * 64 * 64 + src * 64 + dest];
}

fn updateHistory(self: *Game, m: Move, adjustment: i32) void {
    const h = self.getHistory(m);
    const abs_adjustment: i32 = @intCast(@abs(adjustment));
    const grav: i32 = @intCast(@divTrunc(@as(i64, h.*) * abs_adjustment, max_history_value));
    h.* += adjustment - grav;
}

pub fn recordHistory(self: *Game, ply: u32, depth: i32, moves: *const MoveList, i: usize) void {
    const m = moves.moves[i];
    const old_killer = self.getKiller(ply);

    // Record killer move
    if (!m.isTactical()) {
        self.updateKiller(ply, m);
    }

    if (!m.isCapture()) {
        const adjustment: i32 = depth * 1000 - 300;

        // History penalty
        for (moves.moves[0..i]) |badm| {
            if (badm.isCapture() or (m.isPromotion() and m.dest_ptype == .q)) continue;
            if (badm.code.code == old_killer.code) continue;
            self.updateHistory(badm, -adjustment);
        }

        // History bonus
        self.updateHistory(m, adjustment);
    }
}

const Game = @This();
const std = @import("std");
const assert = std.debug.assert;
const common = @import("common.zig");
const coord = @import("coord.zig");
const Board = @import("Board.zig");
const Move = @import("Move.zig");
const MoveCode = @import("MoveCode.zig");
const MoveList = @import("MoveList.zig");
const PieceType = @import("common.zig").PieceType;
const TTEntry = @import("TTEntry.zig");
