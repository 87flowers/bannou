fn contains(limits: []const Limit, limit: Limit) bool {
    return std.mem.containsAtLeast(Limit, limits, 1, &.{limit});
}
const Limit = enum { time, depth, nodes };
pub fn Control(
    comptime limits: []const Limit,
    comptime to_track: struct {
        track_time: bool = false,
        track_nodes: bool = false
    },
) type {
    const needs_timer = to_track.track_time or contains(limits, .time);
    const needs_nodes = to_track.track_nodes or contains(limits, .nodes);
    const has_time_limit = contains(limits, .time);
    const has_depth_limit = contains(limits, .depth);
    const has_nodes_limit = contains(limits, .nodes);

    return struct {
        timer: if (needs_timer) std.time.Timer else void,
        nodes: if (needs_nodes) u64 else void,
        time_limit: if (has_time_limit) struct { soft_deadline: u64, hard_deadline: u64 } else void,
        depth_limit: if (has_depth_limit) struct { target_depth: i32 } else void,
        nodes_limit: if (has_nodes_limit) struct { target_nodes: i32 } else void,

        pub fn init(args: anytype) @This() {
            return .{
                .timer = if (needs_timer) std.time.Timer.start() catch unreachable else {},
                .nodes = if (needs_nodes) 0 else {},
                .time_limit = if (has_time_limit) .{ .soft_deadline = args.soft_deadline, .hard_deadline = args.hard_deadline } else {},
                .depth_limit = if (has_depth_limit) .{ .target_depth = args.target_depth } else {},
                .nodes_limit = if (has_nodes_limit) .{ .target_nodes = args.target_nodes } else {},
            };
        }

        pub fn nodeVisited(self: *@This()) void {
            if (needs_nodes) self.nodes += 1;
        }

        /// Returns true if we should terminate the search
        pub fn checkSoftTermination(self: *@This(), depth: i32) bool {
            if (has_time_limit and self.time_limit.soft_deadline <= self.timer.read()) return true;
            if (has_depth_limit and depth >= self.depth_limit.target_depth) return true;
            if (has_nodes_limit and self.nodes >= self.nodes_limit.target_nodes) return true;
            return false;
        }

        /// Raises SearchError.EarlyTermination if we should terminate the search
        pub fn checkHardTermination(self: *@This(), comptime mode: SearchMode, depth: i32) SearchError!void {
            if (has_time_limit and mode == .normal and depth > 3 and self.time_limit.hard_deadline <= self.timer.read()) return SearchError.EarlyTermination;
            if (has_nodes_limit and self.nodes >= self.nodes_limit.target_nodes) return SearchError.EarlyTermination;
        }

        pub fn format(self: *@This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            if (needs_timer and needs_nodes) {
                const nps = self.nodes * std.time.ns_per_s / self.timer.read();
                try writer.print("time {} nodes {} nps {}", .{ self.timer.read() / std.time.ns_per_ms, self.nodes, nps });
            } else if (needs_timer) {
                try writer.print("time {}", .{self.timer.read() / std.time.ns_per_ms});
            } else if (needs_nodes) {
                try writer.print("nodes {}", .{self.nodes});
            }
        }
    };
}

pub const TimeControl = Control(&.{.time}, .{});
pub const DepthControl = Control(&.{.depth}, .{});

fn search2(game: *Game, ctrl: anytype, pv: anytype, alpha: i32, beta: i32, depth: i32, comptime mode: SearchMode) SearchError!i32 {
    return if (mode != .quiescence and depth <= 0)
        try search(game, ctrl, pv, alpha, beta, depth, .quiescence)
    else if (mode == .firstply)
        try search(game, ctrl, pv, alpha, beta, depth, .normal)
    else
        try search(game, ctrl, pv, alpha, beta, depth, mode);
}

fn search(game: *Game, ctrl: anytype, pv: anytype, alpha: i32, beta: i32, depth: i32, comptime mode: SearchMode) SearchError!i32 {
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
        ctrl.nodeVisited();
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

pub fn go(output: anytype, game: *Game, ctrl: anytype, pv: anytype) !i32 {
    comptime assert(@typeInfo(@TypeOf(ctrl)) == .pointer and @typeInfo(@TypeOf(pv)) == .pointer );
    var depth: i32 = 1;
    var score: i32 = undefined;
    while (depth < 256) : (depth += 1) {
        score = search(game, ctrl, pv, -std.math.maxInt(i32), std.math.maxInt(i32), depth, .firstply) catch {
            try output.print("info depth {} score cp {} {} pv {} string [search terminated]\n", .{ depth, score, ctrl, pv });
            break;
        };
        try output.print("info depth {} score cp {} {} pv {}\n", .{ depth, score, ctrl, pv });
        if (ctrl.checkSoftTermination(depth)) break;
    }
    return score;
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
