const tt_size = 0x1000000;

board: Board,
tt: [tt_size]TTEntry,
killers: [common.max_search_ply]MoveCode,

pub fn reset(self: *Game) void {
    self.board = Board.defaultBoard();
    @memset(&self.tt, TTEntry.empty);
    @memset(&self.killers, MoveCode.none);
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
