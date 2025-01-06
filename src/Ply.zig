value: i32,

pub const granularity = 128;

pub fn fromInt(value: i32) Ply {
    return .{ .value = value * granularity };
}

pub fn int(self: Ply) i32 {
    return @divTrunc(self.value, granularity);
}

pub fn addInt(self: Ply, other: i32) Ply {
    return .{ .value = self.value + other * granularity };
}

pub fn subInt(self: Ply, other: i32) Ply {
    return .{ .value = self.value - other * granularity };
}

pub fn mulTrunc(self: Ply, factor: i32) i32 {
    return @divTrunc(self.value * factor, granularity);
}

pub fn divTrunc(self: Ply, factor: i32) i32 {
    return @divTrunc(self.value, granularity * factor);
}

const Ply = @This();
