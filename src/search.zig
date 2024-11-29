pub const NullControl = struct {
    timer: std.time.Timer,

    pub fn init() NullControl {
        return .{
            .timer = std.time.Timer.start() catch unreachable,
        };
    }

    pub fn timeElapsed(self: *NullControl) u64 {
        return self.timer.read();
    }

    pub fn checkSoftTermination(_: *NullControl, _: i32) bool {
        return false;
    }

    pub fn checkHardTermination(_: *NullControl, comptime _: SearchMode, _: i32) SearchError!void {}
};

pub const TimeControl = struct {
    timer: std.time.Timer,
    soft_deadline: u64,
    hard_deadline: u64,

    pub fn init(soft_deadline: u64, hard_deadline: u64) TimeControl {
        return .{
            .timer = std.time.Timer.start() catch unreachable,
            .soft_deadline = soft_deadline,
            .hard_deadline = hard_deadline,
        };
    }

    pub fn timeElapsed(self: *TimeControl) u64 {
        return self.timer.read();
    }

    pub fn checkSoftTermination(self: *TimeControl, _: i32) bool {
        return self.soft_deadline <= self.timer.read();
    }

    pub fn checkHardTermination(self: *TimeControl, comptime mode: SearchMode, depth: i32) SearchError!void {
        if (mode == .normal and depth > 3) {
            if (self.hard_deadline <= self.timer.read()) return SearchError.EarlyTermination;
        }
    }
};

pub const DepthControl = struct {
    timer: std.time.Timer,
    target_depth: i32,

    pub fn init(target_depth: i32) DepthControl {
        return .{
            .timer = std.time.Timer.start() catch unreachable,
            .target_depth = target_depth,
        };
    }

    pub fn timeElapsed(self: *DepthControl) u64 {
        return self.timer.read();
    }

    pub fn checkSoftTermination(self: *DepthControl, depth: i32) bool {
        return depth >= self.target_depth;
    }

    pub fn checkHardTermination(_: *DepthControl, comptime _: SearchMode, _: i32) SearchError!void {}
};

fn search2(game: *Game, ctrl: anytype, pv: anytype, alpha: i32, beta: i32, depth: i32, comptime mode: SearchMode) SearchError!i32 {
    return if (mode != .quiescence and depth <= 0)
        try search(game, ctrl, pv, alpha, beta, depth, .quiescence)
    else if (mode == .firstply)
        try search(game, ctrl, pv, alpha, beta, depth, .normal)
    else
        try search(game, ctrl, pv, alpha, beta, depth, mode);
}

pub fn search(game: *Game, ctrl: anytype, pv: anytype, alpha: i32, beta: i32, depth: i32, comptime mode: SearchMode) SearchError!i32 {
    // Preconditions for optimizer to be aware of.
    if (mode != .quiescence) assert(depth > 0);
    if (mode == .quiescence) assert(depth <= 0);

    try ctrl.checkHardTermination(mode, depth);

    const tte = game.ttLoad();
    if (tte.hash == game.board.state.hash) {
        if (tte.depth >= depth) {
            const pass = switch (tte.bound) {
                .lower => tte.score >= beta,
                .exact => alpha + 1 == beta,
                .upper => tte.score <= alpha,
            };
            if (pass) {
                pv.write(tte.best_move, &.{});
                return tte.score;
            }
        }
    }

    const no_moves = -std.math.maxInt(i32);
    var best_score: i32 = switch (mode) {
        .firstply, .normal, .nullmove => no_moves,
        .quiescence => eval.eval(game),
    };
    var best_move: MoveCode = tte.best_move;

    // Check stand-pat score for beta cut-off (avoid move generation)
    if (mode == .quiescence and best_score >= beta) {
        pv.writeEmpty();
        return best_score;
    }

    // Null-move pruning
    if (mode == .normal and !game.board.isInCheck() and depth > 4) {
        const old_state = game.board.moveNull();
        defer game.board.unmoveNull(old_state);
        const null_score = -try search2(game, ctrl, line.Null{}, -beta, -beta + 1, depth - 3, .nullmove);
        if (null_score >= beta) {
            pv.writeEmpty();
            return null_score;
        }
    }

    var moves = MoveList{};
    switch (mode) {
        .firstply, .normal, .nullmove => moves.generateMoves(&game.board, .any),
        .quiescence => moves.generateMoves(&game.board, .captures_only),
    }
    moves.sortWithPv(tte.best_move);

    for (0..moves.size) |i| {
        const m = moves.moves[i];
        const old_state = game.board.move(m);
        defer game.board.unmove(m, old_state);
        if (game.board.isValid()) {
            var child_pv = pv.newChild();
            const child_score = if (game.board.isRepeatedPosition() or game.board.is50MoveExpired())
                0
            else
                -try search2(game, ctrl, &child_pv, -beta, -@max(alpha, best_score), depth - 1, mode);
            if (child_score > best_score) {
                best_score = child_score;
                best_move = m.code;
                pv.write(best_move, &child_pv);
                if (child_score >= beta) break;
            }
        }
    }

    if (best_score == no_moves) {
        pv.writeEmpty();
        if (!game.board.isInCheck()) {
            return 0;
        } else {
            return no_moves + 1;
        }
    }
    if (best_score < -1073741824) best_score = best_score + 1;

    if (tte.hash != game.board.state.hash or tte.depth <= depth) {
        game.ttStore(.{
            .hash = game.board.state.hash,
            .best_move = best_move,
            .depth = @intCast(@max(0, depth)),
            .score = best_score,
            .bound = if (best_score >= beta)
                .lower
            else if (best_score <= alpha)
                .upper
            else
                .exact,
        });
    }

    return best_score;
}

pub fn go(output: anytype, game: *Game, ctrl: anytype) !struct { ?MoveCode, i32 } {
    comptime assert(@typeInfo(@TypeOf(ctrl)) == .pointer);
    var depth: i32 = 1;
    var pv = line.RootMove{};
    var score: i32 = undefined;
    while (depth < 256) : (depth += 1) {
        score = search(game, ctrl, &pv, -std.math.maxInt(i32), std.math.maxInt(i32), depth, .firstply) catch {
            try output.print("info depth {} time {} pv {} string [search terminated]\n", .{ depth, ctrl.timeElapsed(), pv });
            break;
        };
        try output.print("info depth {} score cp {} time {} pv {}\n", .{ depth, score, ctrl.timeElapsed(), pv });
        if (ctrl.checkSoftTermination(depth)) break;
    }
    return .{ pv.move, score };
}

const SearchError = error{EarlyTermination};
const SearchMode = enum { firstply, normal, nullmove, quiescence };

const std = @import("std");
const assert = std.debug.assert;
const eval = @import("eval.zig");
const line = @import("line.zig");
const Game = @import("Game.zig");
const MoveCode = @import("MoveCode.zig");
const MoveList = @import("MoveList.zig");
