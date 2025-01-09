pub const Uci = struct {
    writer: std.io.BufferedWriter(4096, std.fs.File.Writer),

    pub inline fn init(writer: std.io.BufferedWriter(4096, std.fs.File.Writer)) Uci {
        return .{ .writer = writer };
    }

    pub inline fn raw(self: *Uci, comptime fmt: []const u8, args: anytype) !void {
        try self.writer.writer().print(fmt, args);
    }

    pub inline fn flush(self: *Uci) !void {
        try self.writer.flush();
    }

    pub fn protocolError(self: *Uci, command: []const u8, comptime fmt: []const u8, args: anytype) !void {
        try self.raw("error ({s}): ", .{command});
        try self.raw(fmt ++ "\n", args);
        try self.flush();
    }

    pub fn unrecognisedToken(self: *Uci, comptime command: []const u8, token: []const u8) !void {
        try self.raw("error (" ++ command ++ "): unrecognised token '{s}'\n", .{token});
        try self.flush();
    }

    pub fn illegalMoveString(self: *Uci, move: []const u8) !void {
        try self.raw("error (illegal move): {s}\n", .{move});
        try self.flush();
    }

    pub fn illegalMove(self: *Uci, move: MoveCode) !void {
        try self.raw("error (illegal move): {}\n", .{move});
        try self.flush();
    }

    pub inline fn pong(self: *Uci) !void {
        try self.raw("readyok\n", .{});
        try self.flush();
    }

    pub inline fn bestmove(self: *Uci, move: ?MoveCode) !void {
        try self.raw("bestmove {?}\n", .{move});
        try self.flush();
    }

    pub inline fn eval(self: *Uci, score: Score) !void {
        try self.printEval(score);
        try self.flush();
    }

    pub inline fn info(self: *Uci, depth: i32, score: Score, ctrl: anytype, pv: anytype, comptime info_type: enum { normal, early_termination }) !void {
        const trailing = switch (info_type) {
            .normal => "\n",
            .early_termination => " string [search terminated]\n",
        };

        const elapsed = ctrl.timer.read();
        const nps = ctrl.nodes * std.time.ns_per_s / elapsed;
        try self.raw("info depth {} score cp {} time {} nodes {} nps {} pv {}" ++ trailing, .{ depth, score, elapsed / std.time.ns_per_ms, ctrl.nodes, nps, pv });
        try self.flush();
    }

    fn printEval(self: *Uci, score: Score) !void {
        if (@import("eval.zig").distanceToMate(score)) |md| {
            try self.raw("score mate {}", .{md});
        } else {
            try self.raw("score cp {}", .{score});
        }
    }
};

const std = @import("std");
const MoveCode = @import("MoveCode.zig");
const Score = @import("eval.zig").Score;
