const std = @import("std");
const builtin = @import("builtin");
const extras = @import("extras");
const nio = @import("./nio.zig");

const sys = switch (builtin.target.os.tag) {
    .linux => @import("sys-linux"),
    .freebsd => @import("sys-freebsd"),
    .netbsd => @import("sys-netbsd"),
    .openbsd => @import("sys-openbsd"),
    else => unreachable,
};

pub fn Base64Writer(comptime WriterType: type) type {
    return struct {
        backing_writer: WriterType,
        alphabet: *const [64]u8,
        buffer: extras.RingBuffer(u8, 3),

        const Self = @This();

        const Alphabet = union(enum) {
            standard,
            url_safe,
            custom: *const [64]u8,
        };

        pub fn init(backing_writer: WriterType, alphabet: Alphabet) Self {
            return .{
                .backing_writer = backing_writer,
                .alphabet = switch (alphabet) {
                    .standard => "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/",
                    .url_safe => "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_",
                    .custom => |a| a,
                },
                .buffer = .empty,
            };
        }

        pub fn from(backing_writer: anytype, alphabet: Alphabet) Base64Writer(@TypeOf(backing_writer)) {
            return .init(backing_writer, alphabet);
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
            var count: usize = 0;
            var fbs: nio.FixedBufferStream([]const u8) = .init(bytes);
            while (true) {
                const len = fbs.read(self.buffer.rest()) catch comptime unreachable;
                self.buffer.len += len;
                count += len;
                if (len == 0) {
                    break;
                }
                if (self.buffer.len == 3) {
                    const i: u24 = @bitCast(self.buffer.items);
                    const P = packed struct(u24) { n3: u6, n2: u6, n1: u6, n0: u6 };
                    const p: P = @bitCast(@byteSwap(i));
                    try self.backing_writer.writeAll(&.{
                        self.alphabet[p.n0],
                        self.alphabet[p.n1],
                        self.alphabet[p.n2],
                        self.alphabet[p.n3],
                    });
                    self.buffer.len = 0;
                }
            }
            return count;
        }

        pub fn writev(self: *Self, iovec: []const sys.struct_iovec) WriteError!usize {
            var count: usize = 0;
            for (iovec) |vec| {
                const len = try write(self, vec.base[0..vec.len]);
                if (len == 0) break;
                count += len;
            }
            return count;
        }

        pub fn anyWritable(self: *Self) nio.AnyWritable {
            const S = struct {
                fn write(s: *allowzero anyopaque, buffer: []const u8) anyerror!usize {
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
            switch (self.buffer.len) {
                else => unreachable,
                3 => unreachable,
                2 => {
                    const n: u16 = @bitCast(self.buffer.items[0..2].*);
                    const i: u18 = @byteSwap(n);
                    const P = packed struct(u18) { n2: u6, n1: u6, n0: u6 };
                    const p: P = @bitCast(i << 2);
                    try self.backing_writer.writeAll(&.{
                        self.alphabet[p.n0],
                        self.alphabet[p.n1],
                        self.alphabet[p.n2],
                        '=',
                    });
                    self.buffer.len = 0;
                },
                1 => {
                    const n: u8 = @bitCast(self.buffer.items[0..1].*);
                    const i: u12 = @byteSwap(n);
                    const P = packed struct(u12) { n1: u6, n0: u6 };
                    const p: P = @bitCast(i << 4);
                    try self.backing_writer.writeAll(&.{
                        self.alphabet[p.n0],
                        self.alphabet[p.n1],
                        '=',
                        '=',
                    });
                    self.buffer.len = 0;
                },
                0 => {},
            }
        }
    };
}
