const std = @import("std");
const builtin = @import("builtin");
const extras = @import("extras");
const sys_linux = @import("sys-linux");

const sys = switch (builtin.target.os.tag) {
    .linux => sys_linux,
    else => unreachable,
};

const nio = @import("./nio.zig");

pub fn FixedBufferStream(comptime Buffer: type) type {
    comptime std.debug.assert(Buffer == []u8 or Buffer == []const u8);
    return struct {
        buffer: Buffer,
        pos: usize,

        const is_const = Buffer == []const u8;

        const Self = @This();

        pub fn init(buffer: Buffer) Self {
            return .{
                .buffer = buffer,
                .pos = 0,
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

        pub const ReadError = error{};
        pub fn read(self: *Self, dest: []u8) ReadError!usize {
            const size = @min(dest.len, self.buffer.len - self.pos);
            const end = self.pos + size;
            @memcpy(dest[0..size], self.buffer[self.pos..end]);
            self.pos = end;
            return size;
        }

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

        const W = nio.Writable(@This(), ._var);
        pub const writeAll = W.writeAll;
        pub const writevAll = W.writevAll;
        pub const writeByteNTimes = W.writeByteNTimes;
        pub const writeNTimes = W.writeNTimes;
        pub const writeInt = W.writeInt;
        pub const writeStruct = W.writeStruct;
        pub const writeIntPretty = W.writeIntPretty;
        pub const print = W.print;

        pub const WriteError = error{NoSpaceLeft};
        /// If the returned number of bytes written is less than requested, the buffer is full.
        /// Returns `error.NoSpaceLeft` when no bytes would be written.
        pub fn write(self: *Self, bytes: []const u8) WriteError!usize {
            if (bytes.len == 0) return 0;
            if (self.pos >= self.buffer.len) return error.NoSpaceLeft;
            const n = @min(self.buffer.len - self.pos, bytes.len);
            @memcpy(self.buffer[self.pos..][0..n], bytes[0..n]);
            self.pos += n;
            if (n == 0) return error.NoSpaceLeft;
            return n;
        }
        pub fn writev(self: *Self, iovec: []const sys.struct_iovec) WriteError!usize {
            var count: usize = 0;
            for (iovec) |vec| {
                const actual = try write(self, vec.base[0..vec.len]);
                count += actual;
                if (actual < vec.len) break;
            }
            return count;
        }

        pub fn anyWritable(self: *Self) nio.AnyWritable {
            const S = struct {
                fn write(s: *allowzero anyopaque, buffer: []const u8) anyerror!usize {
                    const fbs: *Self = @ptrCast(@alignCast(s));
                    return fbs.write(buffer);
                }
            };
            return .{
                .vtable = &.{ .write = S.write },
                .state = @ptrCast(self),
            };
        }

        pub fn written(self: *Self) Buffer {
            return self.buffer[0..self.pos];
        }

        pub fn rest(self: *Self) Buffer {
            return self.buffer[self.pos..];
        }

        pub fn takeArray(self: *Self, comptime len: usize) (if (is_const) *const [len]u8 else *[len]u8) {
            defer self.pos += len;
            return self.rest()[0..len];
        }

        pub fn takeSlice(self: *Self, count: usize) Buffer {
            defer self.pos += count;
            return self.rest()[0..count];
        }

        pub fn takeInt(self: *Self, I: type, endian: std.builtin.Endian) I {
            comptime std.debug.assert(@bitSizeOf(I) % 8 == 0);
            return std.mem.readInt(I, self.takeArray(@sizeOf(I)), endian);
        }

        pub fn takeIntSlice(self: *Self, I: type, len: usize) (if (is_const) []align(1) const I else []align(1) I) {
            comptime std.debug.assert(@bitSizeOf(I) % 8 == 0);
            return @ptrCast(self.takeSlice(@sizeOf(I) * len));
        }
    };
}
