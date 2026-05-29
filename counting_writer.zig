const std = @import("std");
const builtin = @import("builtin");
const extras = @import("extras");
const nio = @import("./nio.zig");

const sys = switch (builtin.target.os.tag) {
    .linux => @import("sys-linux"),
    .macos => @import("sys-darwin"),
    else => unreachable,
};

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
        pub fn writev(self: *Self, iovec: []const sys.struct_iovec) WriteError!usize {
            const len = try self.backing_writer.writev(iovec);
            self.bytes_written += len;
            return len;
        }

        pub fn anyWritable(self: *Self) nio.AnyWritable {
            const S = struct {
                fn write(s: *allowzero anyopaque, buffer: []const u8) anyerror!usize {
                    const cw: *Self = @ptrCast(@alignCast(s));
                    return cw.write(buffer);
                }
            };
            return .{
                .vtable = &.{ .write = S.write },
                .state = @ptrCast(self),
            };
        }
    };
}
