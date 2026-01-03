const std = @import("std");

const nio = @import("./nio.zig");
const AnyWritable = @This();

vtable: *const struct {
    write: *const fn (*allowzero anyopaque, []const u8) anyerror!usize,
},
state: *allowzero anyopaque,

pub const WriteError = anyerror;
pub usingnamespace nio.Writable(@This(), ._var);
pub fn write(r: *AnyWritable, buffer: []u8) !usize {
    return r.vtable.write(r.state, buffer);
}
pub fn anyWritable(r: AnyWritable) AnyWritable {
    return r;
}

pub fn fromStd(writer_ptr: anytype) AnyWritable {
    const S = struct {
        fn _write(s: *allowzero anyopaque, buffer: []const u8) !usize {
            const r: @TypeOf(writer_ptr) = @ptrCast(@alignCast(s));
            return r.write(buffer);
        }
    };
    return .{
        .vtable = &.{ .write = &S._write },
        .state = @constCast(@ptrCast(writer_ptr)),
    };
}
