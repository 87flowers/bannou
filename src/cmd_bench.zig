pub fn run(output: anytype, g: *Game) !void {
    var time: u64 = 0;
    var nodes: u64 = 0;

    for (fens) |fen| {
        g.reset();
        try output.print("benching {s}\n", .{fen});
        g.board = try Board.parse(fen);

        var control = search.DepthControl.init(.{ .target_depth = 8 });
        var pv = line.Line{};
        _ = try search.go(output, g, &control, &pv);

        time += control.timer.read();
        nodes += control.nodes;
        try output.print("\n", .{});
    }

    try output.print(
        \\bench results:
        \\nodes: {} nodes
        \\time:  {} seconds
        \\nps:   {} nodes per second
        \\
    , .{
        nodes,
        time / std.time.ns_per_ms,
        nodes * std.time.ns_per_s / time,
    });

    g.reset();
}

const fens = [_][]const u8{
    "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
    "2r3k1/5pp1/1p2p1np/p1q5/P1P3P1/1P1Q1N1P/5PK1/R7 w - - 0 1",
    "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
    "B6b/8/8/8/2K5/4k3/8/b6B w - - 0 1",
    "7k/5K2/5P1p/3p4/6P1/3p4/8/8 w - - 0 1",
    "3k4/8/4K3/2R5/8/8/8/8 w - - 0 1",
    "8/8/p1p5/1p5p/1P5p/8/PPP2K1p/4R1rk w - - 0 1",
    "r3r1k1/ppqb1ppp/8/4p1NQ/8/2P5/PP3PPP/R3R1K1 b - - 0 1",
    "6k1/p2b1ppp/8/8/3N4/1P5P/5PP1/6K1 b - - 0 1",
    "r6r/p6p/1pnpkn2/q1p2p1p/2P5/2P1P3/P4PP1/1RBQKB1R w K - 0 1",
};

const std = @import("std");
const line = @import("line.zig");
const search = @import("search.zig");
const Board = @import("Board.zig");
const Game = @import("Game.zig");
