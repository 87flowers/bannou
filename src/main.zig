const TimeControl = struct {
    wtime: ?u64 = null,
    btime: ?u64 = null,
    winc: ?u64 = null,
    binc: ?u64 = null,
    movestogo: ?u64 = null,
};

var g: Game = undefined;

const Uci = struct {
    output: std.fs.File.Writer,

    fn go(self: *Uci, tc: TimeControl) !void {
        const margin = 100;
        const movestogo = tc.movestogo orelse 30;
        assert(tc.wtime != null and tc.btime != null);
        const time_remaining = switch (g.board.active_color) {
            .white => tc.wtime.?,
            .black => tc.btime.?,
        };
        const safe_time_remaining = (@max(time_remaining, margin) - margin) * std.time.ns_per_ms; // nanoseconds
        const deadline = safe_time_remaining / movestogo; // nanoseconds
        var info = search.TimeControl.init(.{ .soft_deadline = deadline / 2, .hard_deadline = safe_time_remaining / 2 });

        var bestmove = line.RootMove{};
        _ = try search.go(self.output, &g, &info, &bestmove);
        try self.output.print("bestmove {}\n", .{bestmove});
    }

    const Iterator = std.mem.TokenIterator(u8, .any);

    fn uciParsePosition(self: *Uci, it: *Iterator) !void {
        const pos_type = it.next() orelse "startpos";
        if (std.mem.eql(u8, pos_type, "startpos")) {
            g.setPositionDefault();
        } else if (std.mem.eql(u8, pos_type, "fen")) {
            const board_str = it.next() orelse "";
            const color = it.next() orelse "";
            const castling = it.next() orelse "";
            const enpassant = it.next() orelse "";
            const no_capture_clock = it.next() orelse "";
            const ply = it.next() orelse "";
            g.setPosition(Board.parseParts(board_str, color, castling, enpassant, no_capture_clock, ply) catch
                return self.output.print("info string Error: Invalid FEN for position command\n", .{}));
        } else {
            try self.output.print("info string Error: Invalid position type '{s}' for position command\n", .{pos_type});
            return;
        }

        if (it.next()) |moves_str| {
            if (!std.mem.eql(u8, moves_str, "moves"))
                return self.output.print("info string Error: Unexpected token '{s}' in position command\n", .{moves_str});
            try self.uciParseMoveSequence(it);
        }
    }

    fn uciParseUndo(self: *Uci, it: *Iterator) !void {
        const count = std.fmt.parseUnsigned(usize, it.next() orelse "1", 10) catch
            return self.output.print("info string Error: Invalid argument to undo\n", .{});

        // Replay up to current position
        if (!g.undoAndReplay(count))
            return self.output.print("info string Error: Undo count too large\n", .{});
    }

    fn uciParseMoveSequence(self: *Uci, it: *Iterator) !void {
        while (it.next()) |move_str| {
            const code = MoveCode.parse(move_str) catch
                return self.output.print("info string Error: Invalid movecode '{s}'\n", .{move_str});
            if (!g.makeMoveByCode(code)) {
                try self.output.print("info string Error: Illegal move '{}' in position {}\n", .{ code, g.board });
                return;
            }
        }
    }

    fn uciParseGo(self: *Uci, it: *Iterator) !void {
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
        try self.go(tc);
    }

    fn uciParsePerft(self: *Uci, it: *Iterator) !void {
        const depth = std.fmt.parseUnsigned(usize, it.next() orelse "1", 10) catch
            return self.output.print("info string Error: Invalid argument to l.perft\n", .{});
        try cmd_perft.perft(self.output, &g.board, depth);
    }

    fn uciParseBestMove(self: *Uci, it: *Iterator, make_move: enum { make_move, print_only }) !void {
        const depth = std.fmt.parseInt(i32, it.next() orelse "1", 10) catch
            return self.output.print("info string Error: Invalid argument to l.perft\n", .{});
        var ctrl = search.DepthControl.init(.{ .target_depth = depth });
        var pv = line.Line{};
        const score = try search.go(self.output, &g, &ctrl, &pv);
        try self.output.print("score cp {} pv {}\n", .{ score, pv });
        if (make_move == .make_move) {
            if (pv.len > 0) {
                _ = g.makeMoveByCode(pv.pv[0]);
            } else {
                try self.output.print("No valid move.\n", .{});
            }
        }
    }

    pub fn uciParseCommand(self: *Uci, input_line: []const u8) !void {
        var it = std.mem.tokenizeAny(u8, input_line, " \t\r\n");
        const command = it.next() orelse return;
        if (std.mem.eql(u8, command, "position")) {
            try self.uciParsePosition(&it);
        } else if (std.mem.eql(u8, command, "go")) {
            try self.uciParseGo(&it);
        } else if (std.mem.eql(u8, command, "isready")) {
            try self.output.print("readyok\n", .{});
        } else if (std.mem.eql(u8, command, "ucinewgame")) {
            g.reset();
        } else if (std.mem.eql(u8, command, "uci")) {
            try self.output.print("{s}\n", .{
                \\id name Bannou 0.40
                \\id author 87 (87flowers.com)
                \\uciok
            });
        } else if (std.mem.eql(u8, command, "debug")) {
            _ = it.next();
            // TODO: set debug mode based on next argument
        } else if (std.mem.eql(u8, command, "quit")) {
            std.process.exit(0);
        } else if (std.mem.eql(u8, command, "d")) {
            try g.board.debugPrint(self.output);
        } else if (std.mem.eql(u8, command, "move")) {
            try self.uciParseMoveSequence(&it);
        } else if (std.mem.eql(u8, command, "undo")) {
            try self.uciParseUndo(&it);
        } else if (std.mem.eql(u8, command, "perft") or std.mem.eql(u8, command, "l.perft")) {
            try self.uciParsePerft(&it);
        } else if (std.mem.eql(u8, command, "bench")) {
            try cmd_bench.run(self.output, &g);
        } else if (std.mem.eql(u8, command, "bestmove")) {
            try self.uciParseBestMove(&it, .print_only);
        } else if (std.mem.eql(u8, command, "auto")) {
            try self.uciParseBestMove(&it, .make_move);
        } else if (std.mem.eql(u8, command, "eval")) {
            try self.output.print("score cp {}\n", .{eval.eval(&g)});
        } else if (std.mem.eql(u8, command, "history")) {
            for (g.board.zhistory[0 .. g.board.state.ply + 1], 0..) |h, i| {
                try self.output.print("{}: {X}\n", .{ i, h });
            }
        } else {
            try self.output.print("info string Error: Unknown command '{s}'\n", .{command});
        }
    }
};

pub fn main() !void {
    g.reset();

    var uci = Uci{ .output = std.io.getStdOut().writer() };

    const buffer_size = common.max_game_ply * 5;
    var input = std.io.getStdIn().reader();
    var buffer: [buffer_size]u8 = undefined;
    while (try input.readUntilDelimiterOrEof(&buffer, '\n')) |input_line| {
        try uci.uciParseCommand(input_line);
    }
}

const std = @import("std");
const assert = std.debug.assert;
const cmd_bench = @import("cmd_bench.zig");
const cmd_perft = @import("cmd_perft.zig");
const common = @import("common.zig");
const eval = @import("eval.zig");
const line = @import("line.zig");
const search = @import("search.zig");
const Board = @import("Board.zig");
const Game = @import("Game.zig");
const MoveCode = @import("MoveCode.zig");
