const std = @import("std");

const nio = @import("./nio.zig");
const AnyReadable = @This();

vtable: *const struct {
    read: *const fn (*allowzero anyopaque, []u8) anyerror!usize,
},
state: *allowzero anyopaque,

const R = nio.Readable(@This(), ._const);
pub const readAll = R.readAll;
pub const readAtLeast = R.readAtLeast;
pub const readNoEof = R.readNoEof;
pub const readAllAlloc = R.readAllAlloc;
pub const readArray = R.readArray;
pub const readByte = R.readByte;
pub const readUntilDelimiterArrayList = R.readUntilDelimiterArrayList;
pub const readUntilDelimiterAlloc = R.readUntilDelimiterAlloc;
pub const readUntilDelimiterOrEofAlloc = R.readUntilDelimiterOrEofAlloc;
pub const readUntilDelimitersBuf = R.readUntilDelimitersBuf;
pub const readUntilDelimitersArrayList = R.readUntilDelimitersArrayList;
pub const readAlloc = R.readAlloc;
pub const readInt = R.readInt;
pub const readUntilDelimitersAlloc = R.readUntilDelimitersAlloc;

pub const Error = ReadError; // std compat
pub const ReadError = anyerror;
pub fn read(r: AnyReadable, buffer: []u8) !usize {
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
