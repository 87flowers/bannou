const bannou_version = "0.66";

const TimeControl = struct {
    wtime: ?u64 = null,
    btime: ?u64 = null,
    winc: ?u64 = null,
    binc: ?u64 = null,
    movestogo: ?u64 = null,
};

var g: Game = undefined;

const Uci = struct {
    out: output.Uci,

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

        var pv = line.Line{};
        _ = try search.go(&self.out, &g, &info, &pv);
        try self.out.bestmove(if (pv.len > 0) pv.pv[0] else null);
    }

    fn expectToken(self: *Uci, comptime command: []const u8, it: *Iterator, comptime token: []const u8) !bool {
        if (it.next()) |token_str| {
            if (std.mem.eql(u8, token_str, token)) return true;
            try self.out.unrecognisedToken(command, token_str);
        }
        return false;
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
                return self.out.protocolError("position", "invalid fen provided", .{}));
        } else {
            try self.out.unrecognisedToken("position", pos_type);
            return;
        }

        if (try self.expectToken("position", it, "moves")) {
            try self.uciParseMoveSequence(it);
        }
    }

    fn uciParseUndo(self: *Uci, it: *Iterator) !void {
        const count_str = it.next() orelse "1";
        const count = std.fmt.parseUnsigned(usize, count_str, 10) catch return self.out.unrecognisedToken("undo", count_str);

        // Replay up to current position
        if (!g.undoAndReplay(count))
            return self.out.protocolError("undo", "requested undo count too large", .{});
    }

    fn uciParseMoveSequence(self: *Uci, it: *Iterator) !void {
        while (it.next()) |move_str| {
            const code = MoveCode.parse(move_str) catch return self.out.illegalMoveString(move_str);
            if (!g.makeMoveByCode(code)) return self.out.illegalMove(code);
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
            } else {
                try self.out.unrecognisedToken("go", part);
            }
        }
        try self.go(tc);
    }

    fn uciParsePerft(self: *Uci, it: *Iterator) !void {
        const depth_str = it.next() orelse "1";
        const depth = std.fmt.parseUnsigned(usize, depth_str, 10) catch return self.out.unrecognisedToken("perft", depth_str);
        try cmd_perft.perft(&self.out, &g.board, depth);
    }

    fn uciParseAuto(self: *Uci, it: *Iterator) !void {
        const depth_str = it.next() orelse "1";
        const depth: i32 = std.fmt.parseUnsigned(u31, depth_str, 10) catch return self.out.unrecognisedToken("auto", depth_str);
        var ctrl = search.DepthControl.init(.{ .target_depth = depth });
        var pv = line.Line{};
        _ = try search.go(&self.out, &g, &ctrl, &pv);
        if (pv.len > 0) {
            try self.out.bestmove(pv.pv[0]);
            _ = g.makeMoveByCode(pv.pv[0]);
        } else {
            try self.out.bestmove(null);
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
            try self.out.pong();
        } else if (std.mem.eql(u8, command, "ucinewgame")) {
            g.reset();
        } else if (std.mem.eql(u8, command, "uci")) {
            try self.out.raw(
                \\id name Bannou {s}
                \\id author 87 (87flowers.com)
                \\option name Hash type spin default {} min 1 max 65535
                \\option name Threads type spin default 1 min 1 max 1
                \\uciok
                \\
            , .{ bannou_version, TT.default_tt_size_mb });
            try self.out.flush();
        } else if (std.mem.eql(u8, command, "setoption")) {
            if (!try self.expectToken("setoption", &it, "name")) return;
            const name = it.next() orelse return;
            if (std.mem.eql(u8, name, "Threads")) {
                // do nothing
            } else if (std.mem.eql(u8, name, "Hash")) {
                if (!try self.expectToken("setoption", &it, "value")) return;
                const value_str = it.next() orelse return self.out.protocolError("setoption", "no value provided", .{});
                const value = std.fmt.parseUnsigned(u16, value_str, 10) catch 0;
                if (value == 0) return self.out.protocolError("setoption", "invalid value provided", .{});
                try g.tt.setHashSizeMb(value);
            } else {
                return self.out.unrecognisedToken("setoption", name);
            }
        } else if (std.mem.eql(u8, command, "debug")) {
            _ = it.next();
            // TODO: set debug mode based on next argument
        } else if (std.mem.eql(u8, command, "quit")) {
            std.process.exit(0);
        } else if (std.mem.eql(u8, command, "d")) {
            try g.board.debugPrint(&self.out);
        } else if (std.mem.eql(u8, command, "move")) {
            try self.uciParseMoveSequence(&it);
        } else if (std.mem.eql(u8, command, "undo")) {
            try self.uciParseUndo(&it);
        } else if (std.mem.eql(u8, command, "perft") or std.mem.eql(u8, command, "l.perft")) {
            try self.uciParsePerft(&it);
        } else if (std.mem.eql(u8, command, "bench")) {
            try cmd_bench.run(&self.out, &g, .no_stats);
        } else if (std.mem.eql(u8, command, "stats")) {
            try cmd_bench.run(&self.out, &g, .with_stats);
        } else if (std.mem.eql(u8, command, "auto")) {
            try self.uciParseAuto(&it);
        } else if (std.mem.eql(u8, command, "eval")) {
            try self.out.eval(eval.eval(&g));
        } else if (std.mem.eql(u8, command, "history")) {
            for (g.board.zhistory[0 .. g.board.state.ply + 1], 0..) |h, i| {
                try self.out.raw("{}: {X}\n", .{ i, h });
            }
            try self.out.flush();
        } else {
            try self.out.protocolError(command, "unknown command", .{});
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    g = try Game.init(allocator);
    defer g.deinit();

    var uci = Uci{ .out = output.Uci.init(std.io.bufferedWriter(std.io.getStdOut().writer())) };

    // Handle command line arguments
    {
        var args = try std.process.argsWithAllocator(allocator);
        defer args.deinit();
        // skip program name
        _ = args.skip();

        var has_arguments = false;
        while (args.next()) |arg| {
            has_arguments = true;
            try uci.uciParseCommand(arg);
            try uci.out.flush();
        }
        if (has_arguments) return;
    }

    // Handle stdin
    const buffer_size = common.max_game_ply * 5;
    var input = lineReader(buffer_size, std.io.getStdIn().reader());
    while (try input.readLine()) |input_line| {
        try uci.uciParseCommand(input_line);
        try uci.out.flush();
    }
}

const std = @import("std");
const assert = std.debug.assert;
const cmd_bench = @import("cmd_bench.zig");
const cmd_perft = @import("cmd_perft.zig");
const common = @import("common.zig");
const eval = @import("eval.zig");
const line = @import("line.zig");
const lineReader = @import("util/line_reader.zig").lineReader;
const output = @import("output.zig");
const search = @import("search.zig");
const Board = @import("Board.zig");
const Game = @import("Game.zig");
const MoveCode = @import("MoveCode.zig");
const TT = @import("TT.zig");
