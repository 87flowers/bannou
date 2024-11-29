const TimeControl = struct {
    wtime: ?u64 = null,
    btime: ?u64 = null,
    winc: ?u64 = null,
    binc: ?u64 = null,
    movestogo: ?u64 = null,
};

pub fn uciGo(output: anytype, game: *Game, tc: TimeControl) !void {
    const margin = 100;
    const movestogo = tc.movestogo orelse 30;
    assert(tc.wtime != null and tc.btime != null);
    const time_remaining = switch (game.board.active_color) {
        .white => tc.wtime.?,
        .black => tc.btime.?,
    };
    const safe_time_remaining = (@max(time_remaining, margin) - margin) * 1_000_000; // nanoseconds
    const deadline = safe_time_remaining / movestogo; // nanoseconds
    var info = search.TimeControl.init(deadline / 2, safe_time_remaining / 2);

    const bestmove, _ = try search.go(output, game, &info);
    try output.print("bestmove {?}\n", .{bestmove});
}

var g = Game{};

pub fn main() !void {
    var input = std.io.getStdIn().reader();
    var output = std.io.getStdOut().writer();

    var buffer: [2048]u8 = undefined;
    while (try input.readUntilDelimiterOrEof(&buffer, '\n')) |input_line| {
        var it = std.mem.tokenizeAny(u8, input_line, " \t\r\n");
        if (it.next()) |command| {
            if (std.mem.eql(u8, command, "position")) {
                const pos_type = it.next() orelse "startpos";
                if (std.mem.eql(u8, pos_type, "startpos")) {
                    g.board = Board.defaultBoard();
                } else if (std.mem.eql(u8, pos_type, "fen")) {
                    const board_str = it.next() orelse "";
                    const color = it.next() orelse "";
                    const castling = it.next() orelse "";
                    const enpassant = it.next() orelse "";
                    const no_capture_clock = it.next() orelse "";
                    const ply = it.next() orelse "";
                    g.board = Board.parseParts(board_str, color, castling, enpassant, no_capture_clock, ply) catch {
                        try output.print("info string Error: Invalid FEN for position command\n", .{});
                        continue;
                    };
                } else {
                    try output.print("info string Error: Invalid position type '{s}' for position command\n", .{pos_type});
                    continue;
                }
                if (it.next()) |moves_str| {
                    if (!std.mem.eql(u8, moves_str, "moves")) {
                        try output.print("info string Error: Unexpected token '{s}' in position command\n", .{moves_str});
                        continue;
                    }
                    while (it.next()) |move_str| {
                        const code = MoveCode.parse(move_str) catch {
                            try output.print("info string Error: Invalid movecode '{s}'\n", .{move_str});
                            break;
                        };
                        if (!g.board.makeMoveByCode(code)) {
                            try output.print("info string Error: Illegal move '{s}' in position {}\n", .{ move_str, g.board });
                            break;
                        }
                    }
                }
            } else if (std.mem.eql(u8, command, "go")) {
                var tc = TimeControl{};
                while (it.next()) |part| {
                    if (std.mem.eql(u8, part, "wtime")) {
                        const str = it.next() orelse break;
                        tc.wtime = std.fmt.parseUnsigned(u64, str, 10) catch continue;
                    } else if (std.mem.eql(u8, part, "btime")) {
                        const str = it.next() orelse break;
                        tc.btime = std.fmt.parseUnsigned(u64, str, 10) catch continue;
                    } else if (std.mem.eql(u8, part, "winc")) {
                        const str = it.next() orelse break;
                        tc.winc = std.fmt.parseUnsigned(u64, str, 10) catch continue;
                    } else if (std.mem.eql(u8, part, "binc")) {
                        const str = it.next() orelse break;
                        tc.binc = std.fmt.parseUnsigned(u64, str, 10) catch continue;
                    } else if (std.mem.eql(u8, part, "movestogo")) {
                        const str = it.next() orelse break;
                        tc.movestogo = std.fmt.parseUnsigned(u64, str, 10) catch continue;
                    }
                }
                try uciGo(output, &g, tc);
            } else if (std.mem.eql(u8, command, "isready")) {
                try output.print("readyok\n", .{});
            } else if (std.mem.eql(u8, command, "ucinewgame")) {
                g = .{};
            } else if (std.mem.eql(u8, command, "uci")) {
                try output.print("{s}\n", .{
                    \\id name Bannou 0.15
                    \\id author 87 (87flowers.com)
                    \\uciok
                });
            } else if (std.mem.eql(u8, command, "debug")) {
                _ = it.next();
                // TODO: set debug mode based on next argument
            } else if (std.mem.eql(u8, command, "quit")) {
                return;
            } else if (std.mem.eql(u8, command, "d")) {
                try g.board.debugPrint(output);
            } else if (std.mem.eql(u8, command, "l.move")) {
                while (it.next()) |move_str| {
                    const code = MoveCode.parse(move_str) catch {
                        try output.print("info string Error: Invalid movecode '{s}'\n", .{move_str});
                        break;
                    };
                    if (!g.board.makeMoveByCode(code)) {
                        try output.print("info string Error: Illegal move '{s}' in position {}\n", .{ move_str, g.board });
                        break;
                    }
                }
            } else if (std.mem.eql(u8, command, "l.perft")) {
                const depth = std.fmt.parseUnsigned(usize, it.next() orelse "1", 10) catch {
                    try output.print("info string Error: Invalid argument to l.perft\n", .{});
                    continue;
                };
                if (it.next() != null) try output.print("info string Warning: Unexpected extra arguments to l.perft\n", .{});
                try cmd_perft.perft(output, &g.board, depth);
            } else if (std.mem.eql(u8, command, "l.bestmove")) {
                const str = it.next() orelse continue;
                const depth = std.fmt.parseInt(i32, str, 10) catch continue;
                var ctrl = search.NullControl.init();
                var pv = line.Line{};
                const score = try search.search(&g, &ctrl, &pv, -std.math.maxInt(i32), std.math.maxInt(i32), depth, .firstply);
                try output.print("score cp {} pv {}\n", .{ score, pv });
            } else if (std.mem.eql(u8, command, "l.eval")) {
                try output.print("score cp {}\n", .{eval.eval(&g)});
            } else if (std.mem.eql(u8, command, "l.history")) {
                for (g.board.zhistory[0 .. g.board.state.ply + 1], 0..) |h, i| {
                    try output.print("{}: {X}\n", .{ i, h });
                }
            } else if (std.mem.eql(u8, command, "l.auto")) {
                const str = it.next() orelse continue;
                const depth = std.fmt.parseInt(i32, str, 10) catch continue;
                var ctrl = search.NullControl.init();
                var bm = line.RootMove{};
                _ = try search.search(&g, &ctrl, &bm, -std.math.maxInt(i32), std.math.maxInt(i32), depth, .firstply);
                try output.print("{}\n", .{bm});
                if (bm.move) |m| {
                    _ = g.board.makeMoveByCode(m);
                } else {
                    try output.print("No valid move.\n", .{});
                }
                try g.board.debugPrint(output);
            } else {
                try output.print("info string Error: Unknown command '{s}'\n", .{command});
                continue;
            }
        }
    }
}

const std = @import("std");
const assert = std.debug.assert;
const cmd_perft = @import("cmd_perft.zig");
const eval = @import("eval.zig");
const line = @import("line.zig");
const search = @import("search.zig");
const Board = @import("Board.zig");
const Game = @import("Game.zig");
const MoveCode = @import("MoveCode.zig");
