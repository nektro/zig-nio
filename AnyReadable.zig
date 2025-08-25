const std = @import("std");

const nio = @import("./nio.zig");
const AnyReadable = @This();

readFn: *const fn (*anyopaque, []u8) anyerror!usize,
state: *anyopaque,

pub fn read(r: *AnyReadable, buffer: []u8) !usize {
    return r.readFn(r.state, buffer);
}

pub const ReadError = anyerror;
pub usingnamespace nio.Readable(@This(), ._var);
