const max_history_value: i16 = std.math.maxInt(i16);

board: Board,
tt: TT,
killers: [common.max_game_ply]MoveCode,
history: [6 * 64 * 64]i16,
counter_moves: [2 * 6 * 64 * 64 * 64]i16,

base_position: Board = Board.defaultBoard(),
move_history: [common.max_game_ply]struct { ptype: PieceType, code: MoveCode },
move_history_len: usize,

pub fn init(allocator: std.mem.Allocator) !Game {
    return .{
        .board = undefined,
        .tt = try TT.init(allocator),
        .killers = undefined,
        .history = undefined,
        .counter_moves = undefined,
        .base_position = undefined,
        .move_history = undefined,
        .move_history_len = undefined,
    };
}

pub fn deinit(self: *Game) void {
    self.tt.deinit();
}

pub fn reset(self: *Game) void {
    @memset(&self.killers, MoveCode.none);
    @memset(&self.history, 0);
    @memset(&self.counter_moves, 0);
    @memset(&self.move_history, .{ .ptype = .none, .code = MoveCode.none });
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
    self.move_history[self.move_history_len] = .{ .ptype = m.src_place.ptype, .code = m.code };
    self.move_history_len += 1;
    return self.board.move(m);
}

pub fn makeMoveByCode(self: *Game, code: MoveCode) bool {
    const ptype = self.board.board[code.src()].ptype;
    if (!self.board.makeMoveByCode(code))
        return false;
    self.move_history[self.move_history_len] = .{ .ptype = ptype, .code = code };
    self.move_history_len += 1;
    return true;
}

pub fn unmove(self: *Game, m: Move, old_state: State) void {
    assert(self.move_history[self.move_history_len - 1].code.code == m.code.code);
    self.move_history_len -= 1;
    self.board.unmove(m, old_state);
}

pub fn moveNull(self: *Game) State {
    self.move_history[self.move_history_len] = .{ .ptype = .none, .code = MoveCode.none };
    self.move_history_len += 1;
    return self.board.moveNull();
}

pub fn unmoveNull(self: *Game, old_state: State) void {
    assert(self.move_history[self.move_history_len - 1].code.code == MoveCode.none.code);
    self.move_history_len -= 1;
    self.board.unmoveNull(old_state);
}

pub fn prevMoveCode(self: *Game) MoveCode {
    if (self.move_history_len == 0) return MoveCode.none;
    return self.move_history[self.move_history_len - 1].code;
}

pub fn prevMovePD(self: *Game) usize {
    if (self.move_history_len == 0) return 0;
    const prev_move = self.move_history[self.move_history_len - 1];
    const ptype: usize = @intFromEnum(prev_move.ptype) -| 1;
    const dest: usize = prev_move.code.compressedDest();
    return ptype * 64 + dest;
}

pub fn undoAndReplay(self: *Game, plys: usize) bool {
    if (plys > self.move_history_len)
        return false;
    self.move_history_len -= plys;
    self.board.copyFrom(&self.base_position);
    for (self.move_history[0..self.move_history_len]) |m| {
        _ = self.board.makeMoveByCode(m.code);
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
            break :blk self.getHistory(m);
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

fn getHistoryPointers(self: *Game, m: Move) [2]*i16 {
    const ptype: usize = @intFromEnum(m.destPtype()) - 1;
    const color: usize = @intFromEnum(self.board.active_color);
    const proposed_move: usize = m.code.compressedPair();
    const prev_move_pd: usize = self.prevMovePD();
    return .{
        &self.history[ptype * 64 * 64 + proposed_move],
        &self.counter_moves[color * 6 * 64 * 64 * 64 + prev_move_pd * 64 * 64 + proposed_move],
    };
}

fn getHistory(self: *Game, m: Move) i32 {
    const weights: [2]i32 = .{ 1, 1 };
    const history = self.getHistoryPointers(m);
    var result: i32 = 0;
    for (history, weights) |h, w| {
        result += w * h.*;
    }
    return result;
}

fn updateHistory(self: *Game, m: Move, adjustments: [2]i32, sign: i16) void {
    const history = self.getHistoryPointers(m);
    for (history, adjustments) |h, adj_unsat| {
        const adj: i32 = std.math.clamp(adj_unsat, -max_history_value, max_history_value);
        const grav: i16 = @intCast(@divTrunc(@as(i32, h.*) * adj, max_history_value));
        h.* += @intCast(adj * sign - grav);
    }
}

pub fn recordHistory(self: *Game, depth: i32, moves: *const MoveList, i: usize) void {
    const m = moves.moves[i];
    const old_killer = self.getKiller();

    // Record killer move
    if (!m.isTactical()) {
        self.updateKiller(m);
    }

    if (!m.isCapture()) {
        const adjustments: [2]i32 = .{
            depth * 100 - 30,
            depth * 1000 - 300,
        };

        // History penalty
        for (moves.moves[0..i]) |badm| {
            if (badm.isCapture() or (m.isPromotion() and m.destPtype() == .q)) continue;
            if (badm.code.code == old_killer.code) continue;
            self.updateHistory(badm, adjustments, -1);
        }

        // History bonus
        self.updateHistory(m, adjustments, 1);
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
