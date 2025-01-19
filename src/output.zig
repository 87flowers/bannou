pub const Null = struct {
    pub inline fn raw(_: Null, comptime _: []const u8, _: anytype) !void {}
    pub inline fn flush(_: Null) !void {}
    pub fn protocolError(_: Null, _: []const u8, comptime _: []const u8, _: anytype) !void {}
    pub fn unrecognisedToken(_: Null, comptime _: []const u8, _: []const u8) !void {}
    pub fn illegalMoveString(_: Null, _: []const u8) !void {}
    pub fn illegalMove(_: Null, _: MoveCode) !void {}
    pub inline fn pong(_: Null) !void {}
    pub inline fn bestmove(_: Null, _: ?MoveCode) !void {}
    pub inline fn eval(_: Null, _: Score) !void {}
    pub inline fn info(_: Null, _: i32, _: Score, _: anytype, _: anytype, comptime _: enum { normal, early_termination }) !void {}
};

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
        try self.raw("info depth {} ", .{depth});
        try self.printEval(score);
        try self.raw(" time {} nodes {} nps {} pv {}" ++ trailing, .{ elapsed / std.time.ns_per_ms, ctrl.nodes, nps, pv });
        try self.flush();
    }

    inline fn printEval(self: *Uci, score: Score) !void {
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
