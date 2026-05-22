const std = @import("std");
const builtin = @import("builtin");
const extras = @import("extras");
const nio = @import("./nio.zig");

const sys = switch (builtin.target.os.tag) {
    .linux => @import("sys-linux"),
    else => unreachable,
};

pub const NullWriter = struct {
    const W = nio.Writable(@This(), ._var);
    pub const writeAll = W.writeAll;
    pub const writevAll = W.writevAll;
    pub const writeByteNTimes = W.writeByteNTimes;
    pub const writeNTimes = W.writeNTimes;
    pub const writeInt = W.writeInt;
    pub const writeStruct = W.writeStruct;
    pub const writeIntPretty = W.writeIntPretty;
    pub const print = W.print;

    pub const WriteError = error{};
    pub fn write(self: NullWriter, bytes: []const u8) WriteError!usize {
        _ = self;
        return bytes.len;
    }
    pub fn writev(self: NullWriter, iovec: []const sys.struct_iovec) WriteError!usize {
        _ = self;
        var res: u64 = 0;
        for (iovec) |item| res += item.len;
        return res;
    }
};
