const std = @import("std");
const extras = @import("extras");
const nio = @import("./nio.zig");

pub const NullWriter = struct {
    pub const WriteError = error{};
    pub usingnamespace nio.Writable(@This(), ._var);
    pub fn write(self: NullWriter, bytes: []const u8) WriteError!usize {
        _ = self;
        return bytes.len;
    }
};
