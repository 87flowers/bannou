pub const wk = coord.toBit(0x04) | coord.toBit(0x07);
pub const wq = coord.toBit(0x04) | coord.toBit(0x00);
pub const bk = coord.toBit(0x74) | coord.toBit(0x77);
pub const bq = coord.toBit(0x74) | coord.toBit(0x70);
pub const any = wk | wq | bk | bq;

const coord = @import("coord.zig");
