const std = @import("std");

const nio = @import("./nio.zig");
const AnyReadable = @This();

vtable: *const struct {
    read: *const fn (*allowzero anyopaque, []u8) anyerror!usize,
},
state: *allowzero anyopaque,

pub const ReadError = anyerror;
pub usingnamespace nio.Readable(@This(), ._var);
pub fn read(r: *AnyReadable, buffer: []u8) !usize {
    return r.vtable.read(r.state, buffer);
}
pub fn anyReadable(r: AnyReadable) AnyReadable {
    return r;
}

pub fn fromStd(reader_ptr: anytype) AnyReadable {
    const S = struct {
        fn _read(s: *allowzero anyopaque, buffer: []u8) !usize {
            const r: @TypeOf(reader_ptr) = @ptrCast(@alignCast(s));
            return r.read(buffer);
        }
    };
    return .{
        .vtable = &.{ .read = &S._read },
        .state = @constCast(@ptrCast(reader_ptr)),
    };
}
