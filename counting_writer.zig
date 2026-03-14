const std = @import("std");
const extras = @import("extras");
const nio = @import("./nio.zig");

pub fn CountingWriter(WriterType: type) type {
    return struct {
        backing_writer: WriterType,
        bytes_written: u64,

        const Self = @This();

        pub fn init(backing_writer: WriterType) Self {
            return .{
                .backing_writer = backing_writer,
                .bytes_written = 0,
            };
        }

        pub const WriteError = extras.Pointee(WriterType).WriteError;
        pub usingnamespace nio.Writable(@This(), ._var);
        pub fn write(self: *Self, bytes: []const u8) WriteError!usize {
            const len = try self.backing_writer.write(bytes);
            self.bytes_written += len;
            return len;
        }
    };
}
