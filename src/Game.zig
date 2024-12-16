const tt_size = 0x1000000;

board: Board = Board.defaultBoard(),
tt: [tt_size]TTEntry = [1]TTEntry{TTEntry.empty} ** tt_size,
killers: [common.max_search_ply]MoveCode = [1]MoveCode{MoveCode.none} ** common.max_search_ply,

pub fn reset(self: *Game) void {
    self.* = .{};
}

pub fn ttLoad(self: *Game) TTEntry {
    return self.tt[self.board.state.hash % tt_size];
}

pub fn ttStore(self: *Game, tte: TTEntry) void {
    self.tt[self.board.state.hash % tt_size] = tte;
}

pub fn insertKillerMove(self: *Game, ply: u32, move: MoveCode) void {
    self.killers[ply] = move;
}

const Game = @This();
const common = @import("common.zig");
const Board = @import("Board.zig");
const MoveCode = @import("MoveCode.zig");
const TTEntry = @import("TTEntry.zig");
