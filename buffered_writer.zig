const std = @import("std");
const nio = @import("./nio.zig");

pub fn BufferedWriter(comptime buffer_size: usize, comptime WriterType: type) type {
    return struct {
        unbuffered_writer: WriterType,
        buf: [buffer_size]u8,
        end: usize,

        const Self = @This();

        pub fn init(unbuffered_writer: WriterType) Self {
            return .{
                .unbuffered_writer = unbuffered_writer,
                .buf = undefined,
                .end = 0,
            };
        }

        pub const WriteError = WriterType.WriteError;
        pub usingnamespace nio.Writable(@This(), ._var);
        pub fn write(self: *Self, bytes: []const u8) WriteError!usize {
            if (self.end + bytes.len > self.buf.len) {
                try self.flush();
                if (bytes.len > self.buf.len) return self.unbuffered_writer.write(bytes);
            }
            const new_end = self.end + bytes.len;
            @memcpy(self.buf[self.end..new_end], bytes);
            self.end = new_end;
            return bytes.len;
        }

        pub fn anyWritable(self: *Self) nio.AnyWritable {
            const S = struct {
                fn write(s: *allowzero anyopaque, buffer: []u8) anyerror!usize {
                    const bw: *Self = @ptrCast(@alignCast(s));
                    return bw.write(buffer);
                }
            };
            return .{
                .vtable = &.{ .write = S.write },
                .state = @ptrCast(self),
            };
        }

        pub fn flush(self: *Self) !void {
            try self.unbuffered_writer.writeAll(self.buf[0..self.end]);
            self.end = 0;
        }
    };
}
