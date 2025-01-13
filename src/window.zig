const Window = struct {
    lower_bound: Score,
    upper_bound: Score,

    pub inline fn alpha(self: Window) Score {
        return self.lower_bound;
    }
    pub inline fn beta(self: Window) Score {
        return self.upper_bound;
    }
    pub inline fn isNullWindow(_: Window) bool {
        return false;
    }
};

pub fn window(lower_bound: Score, upper_bound: Score) Window {
    return .{ .lower_bound = lower_bound, .upper_bound = upper_bound };
}

const Above = struct {
    bound: Score,

    pub inline fn alpha(self: Above) Score {
        return -self.bound;
    }
    pub inline fn beta(self: Above) Score {
        return -self.bound +| 1;
    }
    pub inline fn isNullWindow(_: Above) bool {
        return true;
    }
};

pub fn above(bound: Score) Above {
    return .{ .bound = bound };
}

const Below = struct {
    bound: Score,

    pub inline fn alpha(self: Below) Score {
        return -self.bound -| 1;
    }
    pub inline fn beta(self: Below) Score {
        return -self.bound;
    }
    pub inline fn isNullWindow(_: Below) bool {
        return true;
    }
};

pub fn below(bound: Score) Below {
    return .{ .bound = bound };
}

const Score = @import("eval.zig").Score;
