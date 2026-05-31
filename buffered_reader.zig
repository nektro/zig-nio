const std = @import("std");
const nio = @import("./nio.zig");
const extras = @import("extras");

pub fn BufferedReader(comptime buffer_size: usize, comptime ReaderType: type) type {
    return struct {
        unbuffered_reader: ReaderType,
        buf: [buffer_size]u8,
        start: usize,
        end: usize,

        const Self = @This();

        pub fn init(unbuffered_reader: ReaderType) Self {
            return .{
                .unbuffered_reader = unbuffered_reader,
                .buf = undefined,
                .start = 0,
                .end = 0,
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
        pub const readUntilDelimiterOrEof = R.readUntilDelimiterOrEof;
        pub const readExpected = R.readExpected;
        pub const skipBytes = R.skipBytes;
        pub const skipUntilDelimiterOrEof = R.skipUntilDelimiterOrEof;

        pub const ReadError = extras.Pointee(ReaderType).ReadError;
        pub fn read(self: *Self, dest: []u8) ReadError!usize {
            // First try reading from the already buffered data onto the destination.
            const current = self.buf[self.start..self.end];
            if (current.len != 0) {
                const to_transfer = @min(current.len, dest.len);
                @memcpy(dest[0..to_transfer], current[0..to_transfer]);
                self.start += to_transfer;
                return to_transfer;
            }

            // If dest is large, read from the unbuffered reader directly into the destination.
            if (dest.len >= buffer_size) {
                return self.unbuffered_reader.read(dest);
            }

            // If dest is small, read from the unbuffered reader into our own internal buffer,
            // and then transfer to destination.
            self.end = try self.unbuffered_reader.read(&self.buf);
            const to_transfer = @min(self.end, dest.len);
            @memcpy(dest[0..to_transfer], self.buf[0..to_transfer]);
            self.start = to_transfer;
            return to_transfer;
        }

        pub fn anyReadable(self: *Self) nio.AnyReadable {
            const S = struct {
                fn read(s: *allowzero anyopaque, buffer: []u8) anyerror!usize {
                    const br: *Self = @ptrCast(@alignCast(s));
                    return br.read(buffer);
                }
            };
            return .{
                .vtable = &.{ .read = S.read },
                .state = @ptrCast(self),
            };
        }
    };
}
