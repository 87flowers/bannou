const tt_size = 0x1000000;

board: Board = Board.defaultBoard(),
tt: [tt_size]TTEntry = [1]TTEntry{TTEntry.empty} ** tt_size,

pub fn reset(self: *Game) void {
    self.* = .{};
}

pub fn ttLoad(self: *Game) TTEntry {
    return self.tt[self.board.state.hash % tt_size];
}

pub fn ttStore(self: *Game, tte: TTEntry) void {
    self.tt[self.board.state.hash % tt_size] = tte;
}

const Game = @This();
const Board = @import("Board.zig");
const TTEntry = @import("TTEntry.zig");
