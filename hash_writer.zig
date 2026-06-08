//! `std.Io.Writer.Hashing` is recommended to use over this but that type owns the hasher so this allows you to print into an existing Hash

const std = @import("std");
const nio = @import("./nio.zig");
const builtin = @import("builtin");

const sys = switch (builtin.target.os.tag) {
    .linux => @import("sys-linux"),
    .macos => @import("sys-darwin"),
    else => unreachable,
};

pub fn HashWriter(comptime Hash: type) type {
    return struct {
        hasher: *Hash,

        pub fn init(hasher: *Hash) @This() {
            return .{
                .hasher = hasher,
            };
        }

        const W = nio.Writable(@This(), ._const);
        pub const writeAll = W.writeAll;
        pub const writevAll = W.writevAll;
        pub const writeByteNTimes = W.writeByteNTimes;
        pub const writeNTimes = W.writeNTimes;
        pub const writeInt = W.writeInt;
        pub const writeStruct = W.writeStruct;
        pub const writeIntPretty = W.writeIntPretty;
        pub const print = W.print;

        pub const WriteError = error{};

        pub fn write(self: *const @This(), bytes: []const u8) WriteError!usize {
            self.hasher.update(bytes);
            return bytes.len;
        }

        pub fn writev(self: *const @This(), iovec: []const sys.struct_iovec) WriteError!usize {
            var count: usize = 0;
            for (iovec) |vec| count += try write(self, vec.base[0..vec.len]);
            return count;
        }
    };
}
