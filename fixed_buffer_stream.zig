const std = @import("std");

const nio = @import("./nio.zig");

pub fn FixedBufferStream(comptime Buffer: type) type {
    comptime std.debug.assert(Buffer == []u8 or Buffer == []const u8);
    return struct {
        buffer: Buffer,
        pos: usize,

        const Self = @This();

        pub fn init(buffer: Buffer) Self {
            return .{
                .buffer = buffer,
                .pos = 0,
            };
        }

        pub const ReadError = error{};
        pub usingnamespace nio.Readable(@This(), ._var);
        pub fn read(self: *Self, dest: []u8) ReadError!usize {
            const size = @min(dest.len, self.buffer.len - self.pos);
            const end = self.pos + size;
            @memcpy(dest[0..size], self.buffer[self.pos..end]);
            self.pos = end;
            return size;
        }

        pub fn anyReadable(self: *Self) nio.AnyReadable {
            const S = struct {
                fn foo(s: *anyopaque, buffer: []u8) anyerror!usize {
                    const fbs: *Self = @ptrCast(@alignCast(s));
                    return fbs.read(buffer);
                }
            };
            return .{
                .readFn = S.foo,
                .state = @ptrCast(self),
            };
        }
    };
}
