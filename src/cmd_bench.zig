pub fn run(out: anytype, g: *Game, comptime stats: enum { with_stats, no_stats }) !void {
    var time: u64 = 0;
    var nodes: u64 = 0;

    var control = search.Control(.{ .depth = true, .stats = stats == .with_stats }).init(.{ .target_depth = 12 });

    for (fens) |fen| {
        g.reset();
        try out.raw("benching {s}\n", .{fen});
        g.board = try Board.parse(fen);

        control.reset();
        var pv = line.Line{};
        _ = try search.go(out, g, &control, &pv);

        time += control.timer.read();
        nodes += control.nodes;
        try out.raw("\n", .{});
    }

    try out.raw(
        \\bench results:
        \\nodes: {} nodes
        \\time:  {} milliseconds
        \\nps:   {} nps
        \\
    , .{
        nodes,
        time / std.time.ns_per_ms,
        nodes * std.time.ns_per_s / time,
    });
    try out.flush();

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
    "8/8/1p1r1k2/p1pPN1p1/P3KnP1/1P6/8/3R4 b - - 0 1",
    "r3r1k1/ppqb1ppp/8/4p1NQ/8/2P5/PP3PPP/R3R1K1 b - - 0 1",
    "6k1/p2b1ppp/8/8/3N4/1P5P/5PP1/6K1 b - - 0 1",
    "r6r/p6p/1pnpkn2/q1p2p1p/2P5/2P1P3/P4PP1/1RBQKB1R w K - 0 1",

    "q5k1/p2p2bp/1p1p2r1/2p1np2/6p1/1PP2PP1/P2PQ1KP/4R1NR b - - 0 1",
    "r1b1qrk1/pp4b1/2pRn1pp/5p2/2n2B2/2N2NPP/PPQ1PPB1/5RK1 w - - 0 1",
    "r1b2rk1/1pqn1pp1/p2bpn1p/8/3P4/2NB1N2/PPQB1PPP/3R1RK1 w - - 0 1",
    "1b1rr1k1/pp1q1pp1/8/NP1p1b1p/1B1Pp1n1/PQR1P1P1/4BP1P/5RK1 w - - 0 1",
    "2r3k1/5pp1/1p2p1np/p1q5/P1P4P/1P1Q1NP1/5PK1/R7 w - - 0 1",
    "2r3k1/5pp1/1p2p1np/p1q5/P1P4P/1P1Q1NP1/5PK1/R7 w - - 0 1",
    "8/6N1/3kNKp1/3p4/4P3/p7/P6b/8 w - - 0 1",
    "rnbqkb1r/ppp1pppp/5n2/8/3PP3/2N5/PP3PPP/R1BQKBNR b KQkq - 0 1",
    "rnbq1b1r/ppp2kpp/3p1n2/8/3PP3/8/PPP2PPP/RNBQKB1R b KQ d3 0 1",
    "r1q1k2r/pb1nbppp/1p2pn2/8/P1PNP3/2B3P1/2QN1PBP/R4RK1 b kq - 0 1",
    "r2r2k1/pq2bppp/1np1bN2/1p2B1P1/5Q2/P4P2/1PP4P/2KR1B1R b - - 0 1",
    "r3kbnr/1b3ppp/pqn5/1pp1P3/3p4/1BN2N2/PP2QPPP/R1BR2K1 w kq - 0 1",
    "rn1qkbnr/pp1b1ppp/8/1Bpp4/3P4/8/PPPNQPPP/R1B1K1NR b KQkq - 0 1",
    "rq6/5k2/p3pP1p/3p2p1/6PP/1PB1Q3/2P5/1K6 w - - 0 1",
    "2r2rk1/1bqnbpp1/1p1ppn1p/pP6/N1P1P3/P2B1N1P/1B2QPP1/R2R2K1 b - - 0 1",
    "r4rk1/pp1n1p1p/1nqP2p1/2b1P1B1/4NQ2/1B3P2/PP2K2P/2R5 w - - 0 1",
    "rnbqk2r/1p3ppp/p7/1NpPp3/QPP1P1n1/P4N2/4KbPP/R1B2B1R b kq - 0 1",

    "4k3/5ppp/8/8/8/8/PPP5/3K4 w - - 0 1",
};

const std = @import("std");
const line = @import("line.zig");
const search = @import("search.zig");
const Board = @import("Board.zig");
const Game = @import("Game.zig");
