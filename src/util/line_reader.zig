pub const LineReaderError = error{BufferTooSmall};

pub fn LineReader(comptime buffer_size: usize, comptime ReaderType: type) type {
    return struct {
        unbuffered_reader: ReaderType,
        buf: [buffer_size]u8 = undefined,
        start: usize = 0,
        end: usize = 0,

        pub const Error = ReaderType.Error;

        const Self = @This();

        pub fn readLine(self: *Self) !?[]u8 {
            while (true) {
                const contents = self.buf[self.start..self.end];
                if (std.mem.indexOfScalar(u8, contents, '\n')) |pos| {
                    self.start += pos + 1;
                    if (self.start == self.end) {
                        self.start = 0;
                        self.end = 0;
                    }
                    return contents[0 .. pos + 1];
                }

                if (self.start != 0) {
                    std.mem.copyForwards(u8, &self.buf, contents);
                    self.start = 0;
                    self.end = contents.len;
                }

                // Buffer is full and we couldn't find a newline character.
                if (self.end == self.buf.len) return LineReaderError.BufferTooSmall;

                const amt_read = try self.unbuffered_reader.read(self.buf[self.end..]);
                self.end += amt_read;
                if (amt_read == 0) return null;
            }
        }
    };
}

pub fn lineReader(comptime buffer_size: usize, unbuffered_reader: anytype) LineReader(buffer_size, @TypeOf(unbuffered_reader)) {
    return .{ .unbuffered_reader = unbuffered_reader };
}

const std = @import("std");
