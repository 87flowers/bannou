pub fn perft(board: *Board, depth: usize) usize {
    if (depth == 0) return 1;
    var result: usize = 0;
    var moves = MoveList{};
    moves.generateMoves(board, .any);
    for (0..moves.size) |i| {
        const m = moves.moves[i];
        const old_state = board.move(m);
        if (board.isValid()) {
            result += perft(board, depth - 1);
        }
        board.unmove(m, old_state);
    }
    return result;
}

pub fn divide(output: anytype, board: *Board, depth: usize) !void {
    if (depth == 0) return;
    var result: usize = 0;
    var moves = MoveList{};
    var timer = try std.time.Timer.start();
    moves.generateMoves(board, .any);
    for (0..moves.size) |i| {
        const m = moves.moves[i];
        const old_state = board.move(m);
        if (board.isValid()) {
            const p = perft(board, depth - 1);
            result += p;
            try output.print("{}: {}\n", .{ m, p });
        }
        board.unmove(m, old_state);
    }
    const elapsed: f64 = @floatFromInt(timer.read());
    try output.print("Nodes searched (depth {}): {}\n", .{ depth, result });
    try output.print("Search completed in {d:.1}ms\n", .{elapsed / std.time.ns_per_ms});
}

const rand = std.crypto.random;
pub fn eval(board: *Board) i32 {
    var score: i32 = 0;
    for (0..16) |w| {
        score += switch (board.pieces[w]) {
            .none => 0,
            .k => 1000000,
            .q => 1000,
            .r => 500,
            .b => 310,
            .n => 300,
            .p => 100,
        };
    }
    for (16..32) |b| {
        score += switch (board.pieces[b]) {
            .none => 0,
            .k => -1000000,
            .q => -1000,
            .r => -500,
            .b => -310,
            .n => -300,
            .p => -100,
        };
    }
    score += rand.intRangeAtMostBiased(i32, -20, 20);
    return switch (board.active_color) {
        .white => score,
        .black => -score,
    };
}

const Bound = enum { lower, exact, upper };
const TTEntry = struct {
    hash: u64,
    best_move: MoveCode,
    depth: u8,
    bound: Bound,
    score: i32,
    pub fn empty() TTEntry {
        return .{
            .hash = 0,
            .best_move = .{ .code = 0 },
            .depth = undefined,
            .bound = undefined,
            .score = undefined,
        };
    }
};
test {
    comptime assert(@sizeOf(TTEntry) == 16);
}

const tt_size = 0x1000000;
var tt: [tt_size]TTEntry = [_]TTEntry{TTEntry.empty()} ** tt_size;

const SearchTimer = struct {
    timer: std.time.Timer,
    deadline: u64,
    safe_time_remaining: u64,
    pub fn init(deadline: u64, safe_time_remaining: u64) SearchTimer {
        return .{
            .timer = std.time.Timer.start() catch unreachable,
            .deadline = deadline,
            .safe_time_remaining = safe_time_remaining,
        };
    }
    pub fn dummy() SearchTimer {
        return .{
            .timer = std.time.Timer.start() catch unreachable,
            .deadline = std.math.maxInt(u64),
            .safe_time_remaining = std.math.maxInt(u64),
        };
    }
    pub fn read(self: *SearchTimer) u64 {
        return self.timer.read();
    }
    pub fn hardExpired(self: *SearchTimer) bool {
        return self.safe_time_remaining / 2 <= self.timer.read();
    }
    pub fn softExpired(self: *SearchTimer) bool {
        return self.deadline / 2 <= self.timer.read();
    }
};
const SearchError = error{
    OutOfTime,
};
const SearchMode = enum { normal, quiescence };
pub fn search2(board: *Board, timer: *SearchTimer, alpha: i32, beta: i32, depth: i32, comptime mode: SearchMode) SearchError!i32 {
    _, const score = if (mode == .normal and depth <= 0)
        try search(board, timer, alpha, beta, depth, .quiescence)
    else
        try search(board, timer, alpha, beta, depth, mode);
    return score;
}
pub fn search(board: *Board, timer: *SearchTimer, alpha: i32, beta: i32, depth: i32, comptime mode: SearchMode) SearchError!struct { ?MoveCode, i32 } {
    if (timer.hardExpired()) return SearchError.OutOfTime;

    // Preconditions for optimizer to be aware of.
    if (mode == .normal) assert(depth > 0);
    if (mode == .quiescence) assert(depth <= 0);

    const tt_index = board.state.hash % tt_size;
    const tte = tt[tt_index];
    if (tte.hash == board.state.hash) {
        if (tte.depth >= depth) {
            const pass = switch (tte.bound) {
                .lower => tte.score >= beta,
                .exact => alpha + 1 == beta,
                .upper => tte.score <= alpha,
            };
            if (pass) return .{ tte.best_move, tte.score };
        }
    }

    const no_moves = -std.math.maxInt(i32);
    var best_score: i32 = switch (mode) {
        .normal => no_moves,
        .quiescence => eval(board),
    };
    var best_move: MoveCode = tte.best_move;

    // Check stand-pat score for beta cut-off (avoid move generation)
    if (mode == .quiescence and best_score >= beta) return .{ null, best_score };

    var moves = MoveList{};
    switch (mode) {
        .normal => moves.generateMoves(board, .any),
        .quiescence => moves.generateMoves(board, .captures_only),
    }
    moves.sortWithPv(tte.best_move);

    for (0..moves.size) |i| {
        const m = moves.moves[i];
        const old_state = board.move(m);
        defer board.unmove(m, old_state);
        if (board.isValid()) {
            const child_score = if (board.isRepeatedPosition() or board.is50MoveExpired())
                0
            else
                -try search2(board, timer, -beta, -@max(alpha, best_score), depth - 1, mode);
            if (child_score > best_score) {
                best_score = child_score;
                best_move = m.code;
            }
            if (best_score > beta) break;
        }
    }

    if (best_score == no_moves) {
        if (!board.isAttacked(board.where[board.active_color.idBase()], board.active_color)) {
            return .{ null, 0 };
        } else {
            return .{ null, no_moves + 1 };
        }
    }
    if (best_score < -1073741824) best_score = best_score + 1;

    if (tte.hash != board.state.hash or tte.depth <= depth) {
        tt[tt_index] = .{
            .hash = board.state.hash,
            .best_move = best_move,
            .depth = @intCast(@max(0, depth)),
            .score = best_score,
            .bound = if (best_score >= beta)
                .lower
            else if (best_score <= alpha)
                .upper
            else
                .exact,
        };
    }

    return .{ best_move, best_score };
}

const TimeControl = struct {
    wtime: ?u64 = null,
    btime: ?u64 = null,
    winc: ?u64 = null,
    binc: ?u64 = null,
    movestogo: ?u64 = null,
};

pub fn uciGo(output: anytype, board: *Board, tc: TimeControl) !void {
    const margin = 100;
    const movestogo = tc.movestogo orelse 30;
    assert(tc.wtime != null and tc.btime != null);
    const time_remaining = switch (board.active_color) {
        .white => tc.wtime.?,
        .black => tc.btime.?,
    };
    const safe_time_remaining = (@max(time_remaining, margin) - margin) * 1_000_000; // nanoseconds
    const deadline = safe_time_remaining / movestogo; // nanoseconds
    var timer = SearchTimer.init(deadline, safe_time_remaining);

    var depth: i32 = 1;
    var rootmove: ?MoveCode = null;
    while (true) : (depth += 1) {
        rootmove, const score = search(board, &timer, -std.math.maxInt(i32), std.math.maxInt(i32), depth, .normal) catch {
            try output.print("info depth {} time {} pv {?} string [hard timeout, deadline = {}]\n", .{ depth, timer.read() / 1_000_000, rootmove, deadline });
            break;
        };
        try output.print("info depth {} score cp {} time {} pv {?}\n", .{ depth, score, timer.read() / 1_000_000, rootmove });
        if (timer.softExpired()) break;
        if (rootmove == null) break;
    }
    try output.print("bestmove {?}\n", .{rootmove});
}

pub fn main() !void {
    var input = std.io.getStdIn().reader();
    var output = std.io.getStdOut().writer();

    var board = Board.defaultBoard();

    var buffer: [2048]u8 = undefined;
    while (try input.readUntilDelimiterOrEof(&buffer, '\n')) |line| {
        var it = std.mem.tokenizeAny(u8, line, " \t\r\n");
        if (it.next()) |command| {
            if (std.mem.eql(u8, command, "position")) {
                const pos_type = it.next() orelse "startpos";
                if (std.mem.eql(u8, pos_type, "startpos")) {
                    board = Board.defaultBoard();
                } else if (std.mem.eql(u8, pos_type, "fen")) {
                    const board_str = it.next() orelse "";
                    const color = it.next() orelse "";
                    const castling = it.next() orelse "";
                    const enpassant = it.next() orelse "";
                    const no_capture_clock = it.next() orelse "";
                    const ply = it.next() orelse "";
                    board = Board.parseParts(board_str, color, castling, enpassant, no_capture_clock, ply) catch {
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
                        if (!board.makeMoveByCode(code)) {
                            try output.print("info string Error: Illegal move '{s}' in position {}\n", .{ move_str, board });
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
                try uciGo(output, &board, tc);
            } else if (std.mem.eql(u8, command, "isready")) {
                try output.print("readyok\n", .{});
            } else if (std.mem.eql(u8, command, "ucinewgame")) {
                @memset(&tt, TTEntry.empty());
            } else if (std.mem.eql(u8, command, "uci")) {
                try output.print("{s}\n", .{
                    \\id name Bannou 0.8
                    \\id author 87 (87flowers.com)
                    \\uciok
                });
            } else if (std.mem.eql(u8, command, "debug")) {
                _ = it.next();
                // TODO: set debug mode based on next argument
            } else if (std.mem.eql(u8, command, "quit")) {
                return;
            } else if (std.mem.eql(u8, command, "d")) {
                board.debugPrint();
            } else if (std.mem.eql(u8, command, "l.move")) {
                while (it.next()) |move_str| {
                    const code = MoveCode.parse(move_str) catch {
                        try output.print("info string Error: Invalid movecode '{s}'\n", .{move_str});
                        break;
                    };
                    if (!board.makeMoveByCode(code)) {
                        try output.print("info string Error: Illegal move '{s}' in position {}\n", .{ move_str, board });
                        break;
                    }
                }
            } else if (std.mem.eql(u8, command, "l.perft")) {
                const depth = std.fmt.parseUnsigned(usize, it.next() orelse "1", 10) catch {
                    try output.print("info string Error: Invalid argument to l.perft\n", .{});
                    continue;
                };
                if (it.next() != null) try output.print("info string Warning: Unexpected extra arguments to l.perft\n", .{});
                try divide(output, &board, depth);
            } else if (std.mem.eql(u8, command, "l.bestmove")) {
                const str = it.next() orelse continue;
                const depth = std.fmt.parseInt(i32, str, 10) catch continue;
                var timer = SearchTimer.dummy();
                try output.print("{any}\n", .{try search(&board, &timer, -std.math.maxInt(i32), std.math.maxInt(i32), depth, .normal)});
            } else if (std.mem.eql(u8, command, "l.eval")) {
                try output.print("{}\n", .{eval(&board)});
            } else if (std.mem.eql(u8, command, "l.history")) {
                for (board.zhistory[0 .. board.state.ply + 1], 0..) |h, i| {
                    try output.print("{}: {X}\n", .{ i, h });
                }
            } else if (std.mem.eql(u8, command, "l.auto")) {
                const str = it.next() orelse continue;
                const depth = std.fmt.parseInt(i32, str, 10) catch continue;
                var timer = SearchTimer.dummy();
                const bm = try search(&board, &timer, -std.math.maxInt(i32), std.math.maxInt(i32), depth, .normal);
                try output.print("{any}\n", .{bm});
                if (bm[0]) |m| {
                    _ = board.makeMoveByCode(m);
                } else {
                    try output.print("No valid move.\n", .{});
                }
                board.debugPrint();
            } else {
                try output.print("info string Error: Unknown command '{s}'\n", .{command});
                continue;
            }
        }
    }
}

const std = @import("std");
const assert = std.debug.assert;
const Board = @import("Board.zig");
const Move = @import("Move.zig");
const MoveCode = @import("MoveCode.zig");
const MoveList = @import("MoveList.zig");
const Prng = @import("Prng.zig");
const State = @import("State.zig");
