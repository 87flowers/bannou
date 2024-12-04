pub const Null = struct {
    pub inline fn newChild(_: *const Null) Null {
        return .{};
    }
    pub inline fn writeEmpty(_: *const Null) void {}
    pub inline fn write(_: *const Null, _: MoveCode, _: *const Null) void {}
};

pub const Line = struct {
    pv: [common.max_search_ply]MoveCode = undefined,
    len: usize = 0,

    pub fn newChild(_: *Line) Line {
        return .{};
    }

    pub fn writeEmpty(self: *Line) void {
        self.len = 0;
    }

    pub fn write(self: *Line, m: MoveCode, rest: *const Line) void {
        self.pv[0] = m;
        @memcpy(self.pv[1 .. rest.len + 1], rest.pv[0..rest.len]);
        self.len = rest.len + 1;
    }

    pub fn format(self: *const Line, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        for (self.pv[0..self.len]) |m| try writer.print("{} ", .{m});
    }
};

pub const RootMove = struct {
    move: ?MoveCode = null,

    pub fn newChild(_: *RootMove) Null {
        return Null{};
    }

    pub inline fn writeEmpty(self: *RootMove) void {
        self.move = null;
    }

    pub inline fn write(self: *RootMove, m: MoveCode, _: *const Null) void {
        self.move = m;
    }

    pub fn format(self: RootMove, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{?}", .{self.move});
    }
};

const std = @import("std");
const common = @import("common.zig");
const MoveCode = @import("MoveCode.zig");
const SearchMode = @import("search.zig").SearchMode;
