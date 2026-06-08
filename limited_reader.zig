const std = @import("std");
const builtin = @import("builtin");
const extras = @import("extras");
const nio = @import("./nio.zig");

const sys = switch (builtin.target.os.tag) {
    .linux => @import("sys-linux"),
    .macos => @import("sys-darwin"),
    else => unreachable,
};

pub fn LimitedReader(ReaderType: type) type {
    return struct {
        backing_reader: ReaderType,
        bytes_left: u64,

        const Self = @This();

        pub fn init(backing_reader: ReaderType, bytes_left: u64) Self {
            return .{
                .backing_reader = backing_reader,
                .bytes_left = bytes_left,
            };
        }

        const R = nio.Readable(@This(), ._var);
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
        pub const readUntilDelimiter = R.readUntilDelimiter;
        pub const readUntilDelimiterOrEof = R.readUntilDelimiterOrEof;
        pub const readExpected = R.readExpected;
        pub const readType = R.readType;
        pub const skipBytes = R.skipBytes;
        pub const skipUntilDelimiterOrEof = R.skipUntilDelimiterOrEof;
        pub const pipeTo = R.pipeTo;

        pub const ReadError = extras.Pointee(ReaderType).ReadError;

        pub fn read(self: *Self, bytes: []u8) ReadError!usize {
            const max_read = @min(self.bytes_left, bytes.len);
            const n = try self.backing_reader.read(bytes[0..max_read]);
            self.bytes_left -= n;
            return n;
        }
        // pub fn readv(self: *Self, iovec: []sys.struct_iovec) ReadError!usize {
        //     const len = try self.backing_reader.readv(iovec);
        //     self.bytes_read += len;
        //     return len;
        // }

        pub fn anyReadable(self: *Self) nio.AnyReadable {
            const S = struct {
                fn read(s: *allowzero anyopaque, buffer: []u8) anyerror!usize {
                    const fbs: *Self = @ptrCast(@alignCast(s));
                    return fbs.read(buffer);
                }
            };
            return .{
                .vtable = &.{ .read = S.read },
                .state = @ptrCast(self),
            };
        }
    };
}
