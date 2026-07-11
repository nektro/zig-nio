const std = @import("std");
const builtin = @import("builtin");
const extras = @import("extras");
const nio = @import("./nio.zig");

pub fn SkipReader(comptime ReaderType: type) type {
    return struct {
        source_reader: ReaderType,
        needles: []const u8,

        const Self = @This();

        pub fn init(source_reader: ReaderType, needles: []const u8) Self {
            return .{
                .source_reader = source_reader,
                .needles = needles,
            };
        }

        pub fn from(source_reader: anytype, needles: []const u8) SkipReader(@TypeOf(source_reader)) {
            return .init(source_reader, needles);
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
        pub fn read(self: *Self, dest: []u8) ReadError!usize {
            var i: usize = 0;
            while (i < dest.len) {
                dest[i] = self.source_reader.readByte() catch |err| switch (err) {
                    error.EndOfStream => break,
                    else => |e| return e,
                };
                if (std.mem.findScalar(u8, self.needles, dest[i]) != null) continue;
                i += 1;
            }
            return i;
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
