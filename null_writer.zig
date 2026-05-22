const std = @import("std");
const extras = @import("extras");
const nio = @import("./nio.zig");

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
};
