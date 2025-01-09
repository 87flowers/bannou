fn core(board: *Board, depth: usize) usize {
    if (depth == 0) return 1;
    var result: usize = 0;
    var moves = MoveList{};
    moves.generateMoves(board, .any);
    for (0..moves.size) |i| {
        const m = moves.moves[i];
        const old_state = board.move(m);
        if (board.isValid()) {
            result += core(board, depth - 1);
        }
        board.unmove(m, old_state);
    }
    return result;
}

pub fn perft(out: anytype, board: *Board, depth: usize) !void {
    if (depth == 0) return;
    var result: usize = 0;
    var moves = MoveList{};
    var timer = try std.time.Timer.start();
    moves.generateMoves(board, .any);
    for (0..moves.size) |i| {
        const m = moves.moves[i];
        const old_state = board.move(m);
        if (board.isValid()) {
            const p = core(board, depth - 1);
            result += p;
            try out.raw("{}: {}\n", .{ m, p });
            try out.flush();
        }
        board.unmove(m, old_state);
    }
    const elapsed: f64 = @floatFromInt(timer.read());
    try out.raw("Nodes searched (depth {}): {}\n", .{ depth, result });
    try out.raw("Search completed in {d:.1}ms\n", .{elapsed / std.time.ns_per_ms});
    try out.flush();
}

const std = @import("std");
const Board = @import("Board.zig");
const MoveList = @import("MoveList.zig");
