const max_history_value: i16 = std.math.maxInt(i16);

board: Board,
tt: TT,
killers: [common.max_game_ply]MoveCode,
history: [6 * 64 * 64]i16,
counter_moves: [2 * 64 * 64]MoveCode,

base_position: Board = Board.defaultBoard(),
move_history: [common.max_game_ply]MoveCode,
move_history_len: usize,

pub fn init(allocator: std.mem.Allocator) !Game {
    var self: Game = undefined;
    self.tt = try TT.init(allocator);
    self.reset();
    return self;
}

pub fn deinit(self: *Game) void {
    self.tt.deinit();
}

pub fn reset(self: *Game) void {
    @memset(&self.killers, MoveCode.none);
    @memset(&self.history, 0);
    @memset(&self.counter_moves, MoveCode.none);
    @memset(&self.move_history, MoveCode.none);
    self.tt.clear();
    self.setPositionDefault();
}

pub fn setPositionDefault(self: *Game) void {
    self.board = Board.defaultBoard();
    self.base_position = Board.defaultBoard();
    self.move_history_len = 0;
}

pub fn setPosition(self: *Game, pos: Board) void {
    self.board.copyFrom(&pos);
    self.base_position.copyFrom(&pos);
    self.move_history_len = 0;
}

pub fn move(self: *Game, m: Move) State {
    self.move_history[self.move_history_len] = m.code;
    self.move_history_len += 1;
    return self.board.move(m);
}

pub fn makeMoveByCode(self: *Game, code: MoveCode) bool {
    if (!self.board.makeMoveByCode(code))
        return false;
    self.move_history[self.move_history_len] = code;
    self.move_history_len += 1;
    return true;
}

pub fn unmove(self: *Game, m: Move, old_state: State) void {
    assert(self.move_history[self.move_history_len - 1].code == m.code.code);
    self.move_history_len -= 1;
    self.board.unmove(m, old_state);
}

pub fn moveNull(self: *Game) State {
    self.move_history[self.move_history_len] = MoveCode.none;
    self.move_history_len += 1;
    return self.board.moveNull();
}

pub fn unmoveNull(self: *Game, old_state: State) void {
    assert(self.move_history[self.move_history_len - 1].code == MoveCode.none.code);
    self.move_history_len -= 1;
    self.board.unmoveNull(old_state);
}

pub fn prevMove(self: *Game) MoveCode {
    if (self.move_history_len == 0) return MoveCode.none;
    return self.move_history[self.move_history_len - 1];
}

pub fn undoAndReplay(self: *Game, plys: usize) bool {
    if (plys > self.move_history_len)
        return false;
    self.move_history_len -= plys;
    self.board.copyFrom(&self.base_position);
    for (self.move_history[0..self.move_history_len]) |code| {
        _ = self.board.makeMoveByCode(code);
    }
    return true;
}

pub fn ttLoad(self: *Game) TT.Entry {
    return self.tt.load(self.board.state.hash);
}

pub fn ttStore(self: *Game, arg: struct {
    depth: u7,
    best_move: MoveCode,
    bound: TT.Bound,
    score: Score,
}) void {
    self.tt.store(self.board.state.hash, arg.depth, arg.best_move, arg.bound, arg.score);
}

pub fn sortMoves(self: *Game, moves: *MoveList, tt_move: MoveCode) void {
    const killer = self.getKiller();
    const counter_move = self.getCounter();

    var sort_scores: [common.max_legal_moves]i32 = undefined;
    for (0..moves.size) |i| {
        const m = moves.moves[i];
        sort_scores[i] = blk: {
            if (m.code.code == tt_move.code)
                break :blk @as(i32, 127 << 24);
            if (m.isCapture())
                break :blk @as(i32, 125 << 24) + (@as(i32, @intFromEnum(m.capture_place.ptype)) << 8) - @intFromEnum(m.srcPtype());
            if (m.isPromotion() and m.destPtype() == .q)
                break :blk @as(i32, 124 << 24);
            if (m.code.code == killer.code)
                break :blk @as(i32, 123 << 24) + 1;
            if (m.code.code == counter_move.code)
                break :blk @as(i32, 123 << 24) + 0;
            break :blk self.getHistory(m).*;
        };
    }
    moves.sortInOrder(&sort_scores);
}

pub fn killerClearChild(self: *Game) void {
    self.killers[self.move_history_len + 1] = MoveCode.none;
}

fn getKiller(self: *Game) MoveCode {
    return self.killers[self.move_history_len];
}

fn updateKiller(self: *Game, m: Move) void {
    self.killers[self.move_history_len] = m.code;
}

fn getCounter(self: *Game) MoveCode {
    const index = @as(usize, self.prevMove().compressedPair()) +
        @as(usize, @intFromEnum(self.board.active_color)) * 64 * 64;
    return self.counter_moves[index];
}

fn updateCounter(self: *Game, m: Move) void {
    const index = @as(usize, self.prevMove().compressedPair()) +
        @as(usize, @intFromEnum(self.board.active_color)) * 64 * 64;
    self.counter_moves[index] = m.code;
}

fn getHistory(self: *Game, m: Move) *i16 {
    const ptype: usize = @intFromEnum(m.destPtype()) - 1;
    return &self.history[ptype * 64 * 64 + m.code.compressedPair()];
}

fn updateHistory(self: *Game, m: Move, adjustment: i16) void {
    const h = self.getHistory(m);
    const abs_adjustment: i16 = @intCast(@abs(adjustment));
    const grav: i16 = @intCast(@divTrunc(@as(i32, h.*) * abs_adjustment, max_history_value));
    h.* += adjustment - grav;
}

pub fn recordHistory(self: *Game, depth: i32, moves: *const MoveList, i: usize) void {
    const m = moves.moves[i];
    const old_killer = self.getKiller();
    const old_counter = self.getCounter();

    // Record killer move
    if (!m.isTactical()) {
        self.updateKiller(m);
        self.updateCounter(m);
    }

    if (!m.isCapture()) {
        const adjustment: i16 = @intCast(depth * 100 - 70);

        // History penalty
        for (moves.moves[0..i]) |badm| {
            if (badm.isCapture() or (m.isPromotion() and m.destPtype() == .q)) continue;
            if (badm.code.code == old_killer.code) continue;
            if (badm.code.code == old_counter.code) continue;
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
const Score = @import("eval.zig").Score;
const State = @import("State.zig");
const TT = @import("TT.zig");
