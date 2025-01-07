fn core(g: *Game, depth: usize) usize {
    if (depth == 0) return 1;
    var result: usize = 0;
    var moves = MoveList{};
    moves.generateMoves(g.board(), .any);
    for (0..moves.size) |i| {
        const m = moves.moves[i];
        g.move(m);
        if (g.board().isValid()) {
            result += core(g, depth - 1);
        }
        g.unmove();
    }
    return result;
}

pub fn perft(output: anytype, g: *Game, depth: usize) !void {
    if (depth == 0) return;
    var result: usize = 0;
    var moves = MoveList{};
    var timer = try std.time.Timer.start();
    moves.generateMoves(g.board(), .any);
    for (0..moves.size) |i| {
        const m = moves.moves[i];
        g.move(m);
        if (g.board().isValid()) {
            const p = core(g, depth - 1);
            result += p;
            try output.print("{}: {}\n", .{ m, p });
        }
        g.unmove();
    }
    const elapsed: f64 = @floatFromInt(timer.read());
    try output.print("Nodes searched (depth {}): {}\n", .{ depth, result });
    try output.print("Search completed in {d:.1}ms\n", .{elapsed / std.time.ns_per_ms});
}

const std = @import("std");
const Board = @import("Board.zig");
const Game = @import("Game.zig");
const MoveList = @import("MoveList.zig");
