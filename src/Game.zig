const max_history_value: i32 = 1 << 24;

tt: TT,
killers: [common.max_game_ply]MoveCode,
history: [6 * 64 * 64]i32,
counter_moves: [2 * 64 * 64]MoveCode,

board_history: [common.max_game_ply]Board,
move_history: [common.max_game_ply]MoveCode,
hash_history: [common.max_game_ply]Hash,
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
    self.board_history[0] = comptime Board.defaultBoard();
    self.hash_history[0] = comptime Board.defaultBoard().calcHashSlow();
    self.move_history_len = 0;
}

pub fn setPosition(self: *Game, pos: Board) void {
    self.board_history[0] = pos;
    self.hash_history[0] = pos.calcHashSlow();
    self.move_history_len = 0;
}

pub fn board(self: *const Game) *const Board {
    return &self.board_history[self.move_history_len];
}

pub fn hash(self: *const Game) Hash {
    return self.hash_history[self.move_history_len];
}

pub fn move(self: *Game, m: Move) void {
    self.move_history[self.move_history_len] = m.code;
    self.move_history_len += 1;
    self.hash_history[self.move_history_len] = self.board_history[self.move_history_len].move(&self.board_history[self.move_history_len - 1], m, self.hash_history[self.move_history_len - 1]);
    assert(self.hash_history[self.move_history_len] == self.board_history[self.move_history_len].calcHashSlow());
}

pub fn makeMoveByCode(self: *Game, code: MoveCode) bool {
    self.move_history[self.move_history_len] = code;
    self.move_history_len += 1;
    self.hash_history[self.move_history_len] = self.board_history[self.move_history_len].makeMoveByCode(&self.board_history[self.move_history_len - 1], code, self.hash_history[self.move_history_len - 1]) orelse return false;
    assert(self.hash_history[self.move_history_len] == self.board_history[self.move_history_len].calcHashSlow());
    return true;
}

pub fn moveNull(self: *Game) void {
    self.move_history[self.move_history_len] = MoveCode.none;
    self.move_history_len += 1;
    self.hash_history[self.move_history_len] = self.board_history[self.move_history_len].moveNull(&self.board_history[self.move_history_len - 1], self.hash_history[self.move_history_len - 1]);
    assert(self.hash_history[self.move_history_len] == self.board_history[self.move_history_len].calcHashSlow());
}

pub fn unmove(self: *Game) void {
    self.move_history_len -= 1;
    assert(self.hash_history[self.move_history_len] == self.board_history[self.move_history_len].calcHashSlow());
}

pub fn prevMove(self: *const Game) MoveCode {
    if (self.move_history_len == 0) return MoveCode.none;
    return self.move_history[self.move_history_len - 1];
}

pub fn isRepeatedPosition(self: *const Game) bool {
    var i: i32 = @intCast(self.move_history_len);
    var ncc: i32 = @intCast(self.board().state.no_capture_clock);

    if (i < 4 or ncc < 4) return false;

    const h = self.hash();

    i -= 4;
    ncc -= 4;

    while (i >= 0 and ncc >= 0) {
        if (self.hash_history[@intCast(i)] == h) return true;
        i -= 2;
        ncc -= 2;
    }

    return false;
}

pub fn ttLoad(self: *Game) TT.Entry {
    return self.tt.load(self.hash());
}

pub fn ttStore(self: *Game, arg: struct {
    depth: u7,
    best_move: MoveCode,
    bound: TT.Bound,
    score: Score,
}) void {
    self.tt.store(self.hash(), arg.depth, arg.best_move, arg.bound, arg.score);
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

fn getKiller(self: *const Game) MoveCode {
    return self.killers[self.move_history_len];
}

fn updateKiller(self: *Game, m: Move) void {
    self.killers[self.move_history_len] = m.code;
}

fn getCounter(self: *const Game) MoveCode {
    const index = @as(usize, self.prevMove().compressedPair()) +
        @as(usize, @intFromEnum(self.board().active_color)) * 64 * 64;
    return self.counter_moves[index];
}

fn updateCounter(self: *Game, m: Move) void {
    const index = @as(usize, self.prevMove().compressedPair()) +
        @as(usize, @intFromEnum(self.board().active_color)) * 64 * 64;
    self.counter_moves[index] = m.code;
}

fn getHistory(self: *Game, m: Move) *i32 {
    const ptype: usize = @intFromEnum(m.destPtype()) - 1;
    return &self.history[ptype * 64 * 64 + m.code.compressedPair()];
}

fn updateHistory(self: *Game, m: Move, adjustment: i32) void {
    const h = self.getHistory(m);
    const abs_adjustment: i32 = @intCast(@abs(adjustment));
    const grav: i32 = @intCast(@divTrunc(@as(i64, h.*) * abs_adjustment, max_history_value));
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
        const adjustment: i32 = depth * 1000 - 300;

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
const Hash = @import("zhash.zig").Hash;
const Move = @import("Move.zig");
const MoveCode = @import("MoveCode.zig");
const MoveList = @import("MoveList.zig");
const PieceType = @import("common.zig").PieceType;
const Score = @import("eval.zig").Score;
const State = @import("State.zig");
const TT = @import("TT.zig");
