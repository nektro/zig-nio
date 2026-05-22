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

        const W = nio.Writable(@This(), ._var);
        pub const writeAll = W.writeAll;
        pub const writevAll = W.writevAll;
        pub const writeByteNTimes = W.writeByteNTimes;
        pub const writeNTimes = W.writeNTimes;
        pub const writeInt = W.writeInt;
        pub const writeStruct = W.writeStruct;
        pub const writeIntPretty = W.writeIntPretty;
        pub const print = W.print;

        pub const WriteError = extras.Pointee(WriterType).WriteError;
        pub fn write(self: *Self, bytes: []const u8) WriteError!usize {
            const len = try self.backing_writer.write(bytes);
            self.bytes_written += len;
            return len;
        }
    };
}
