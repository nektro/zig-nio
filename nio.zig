const std = @import("std");
const builtin = @import("builtin");
const extras = @import("extras");
const sys_linux = @import("sys-linux");

pub const fmt = @import("./fmt.zig");

const sys = switch (builtin.target.os.tag) {
    .linux => sys_linux,
    .macos => @import("sys-darwin"),
    else => unreachable,
};

pub fn Readable(T: type, this_kind: enum { _var, _const, _bare }) type {
    return struct {
        const Error = T.ReadError;

        const Self = switch (this_kind) {
            ._var => *T,
            ._const => *const T,
            ._bare => T,
        };

        /// Returns the number of bytes read. It may be less than buffer.len.
        /// If the number of bytes read is 0, it means end of stream.
        /// End of stream is not an error condition.
        // pub fn read(self: Self, buffer: []u8) Error!usize {
        // }

        /// Returns the number of bytes read. If the number read is smaller than `buffer.len`, it
        /// means the stream reached the end. Reaching the end of a stream is not an error
        /// condition.
        pub fn readAll(self: Self, buffer: []u8) Error!usize {
            return readAtLeast(self, buffer, buffer.len);
        }

        /// Returns the number of bytes read, calling the underlying read
        /// function the minimal number of times until the buffer has at least
        /// `len` bytes filled. If the number read is less than `len` it means
        /// the stream reached the end. Reaching the end of the stream is not
        /// an error condition.
        pub fn readAtLeast(self: Self, buffer: []u8, len: usize) Error!usize {
            std.debug.assert(len <= buffer.len);
            var index: usize = 0;
            while (index < len) {
                const amt = try self.read(buffer[index..]);
                if (amt == 0) break;
                index += amt;
            }
            return index;
        }

        /// If the number read would be smaller than `buf.len`, `error.EndOfStream` is returned instead.
        pub fn readNoEof(self: Self, buf: []u8) (Error || error{EndOfStream})!void {
            const amt_read = try readAll(self, buf);
            if (amt_read < buf.len) return error.EndOfStream;
        }

        /// Appends to the `std.ArrayList` contents by reading from the stream until end of stream is found.
        /// If the number of bytes appended would exceed `max_append_size`, `error.StreamTooLong` is returned and the `std.ArrayList` has exactly `max_append_size` bytes appended.
        fn readAllArrayList(self: Self, array_list: *std.array_list.Managed(u8), max_append_size: usize) !void {
            return readAllArrayListAligned(self, null, array_list, max_append_size);
        }

        fn readAllArrayListAligned(self: Self, comptime alignment: ?std.mem.Alignment, array_list: *std.array_list.AlignedManaged(u8, alignment), max_append_size: usize) !void {
            try array_list.ensureTotalCapacity(@min(max_append_size, 4096));
            const original_len = array_list.items.len;
            var start_index: usize = original_len;
            while (true) {
                array_list.expandToCapacity();
                const dest_slice = array_list.items[start_index..];
                const bytes_read = try readAll(self, dest_slice);
                start_index += bytes_read;

                if (start_index - original_len > max_append_size) {
                    array_list.shrinkAndFree(original_len + max_append_size);
                    return error.StreamTooLong;
                }

                if (bytes_read != dest_slice.len) {
                    array_list.shrinkAndFree(start_index);
                    return;
                }

                // This will trigger ArrayList to expand superlinearly at whatever its growth rate is.
                try array_list.ensureTotalCapacity(start_index + 1);
            }
        }

        /// Allocates enough memory to hold all the contents of the stream.
        /// If the allocated memory would be greater than `max_size`, returns `error.StreamTooLong`.
        /// Caller owns returned memory.
        /// If this function returns an error, the contents from the stream read so far are lost.
        pub fn readAllAlloc(self: Self, allocator: std.mem.Allocator, max_size: usize) ![]u8 {
            var array_list = std.array_list.Managed(u8).init(allocator);
            defer array_list.deinit();
            try readAllArrayList(self, &array_list, max_size);
            return try array_list.toOwnedSlice();
        }

        pub fn readArray(self: Self, comptime N: usize) ![N]u8 {
            var buffer: [N]u8 = undefined;
            if (try readAll(self, &buffer) != N) return error.EndOfStream;
            return buffer;
        }

        pub fn readByte(self: Self) !u8 {
            return (try readArray(self, 1))[0];
        }

        /// Returned slice is not suffixed by needle but array_list will contain it.
        pub fn readUntilDelimiterArrayList(self: Self, array_list: *std.array_list.Managed(u8), needle: u8, max_size: usize) ![]u8 {
            const initial_len = array_list.items.len;
            for (0..max_size) |i| {
                try array_list.append(try readByte(self));
                if (array_list.items[array_list.items.len - 1] == needle) return array_list.items[initial_len..][0..i];
            }
            return error.StreamTooLong;
        }

        /// Returned slice is suffixed by needle.
        pub fn readUntilDelimiterAlloc(self: Self, allocator: std.mem.Allocator, needle: u8, max_size: usize) ![]u8 {
            var list: std.array_list.Managed(u8) = .init(allocator);
            errdefer list.deinit();
            _ = try readUntilDelimiterArrayList(self, &list, needle, max_size);
            return list.toOwnedSlice();
        }

        pub fn readUntilDelimiterOrEofAlloc(self: Self, allocator: std.mem.Allocator, needle: u8, max_size: usize) !?[]u8 {
            var list: std.array_list.Managed(u8) = .init(allocator);
            defer list.deinit();
            _ = readUntilDelimiterArrayList(self, &list, needle, max_size) catch |err| switch (err) {
                error.EndOfStream => return null,
                else => |e| return e,
            };
            return try list.toOwnedSlice();
        }

        /// Returned slice is not suffixed by needle but buffer will contain it.
        pub fn readUntilDelimitersBuf(self: Self, buffer: []u8, needle: []const u8) ![]u8 {
            var real_len: usize = 0;
            for (0..buffer.len) |_| {
                buffer[real_len] = try readByte(self);
                real_len += 1;
                if (real_len < needle.len) continue;
                if (std.mem.endsWith(u8, buffer[0..real_len], needle)) return buffer[0 .. real_len - needle.len];
            }
            return error.StreamTooLong;
        }

        /// Returned slice is not suffixed by needle but array_list will contain it.
        pub fn readUntilDelimitersArrayList(self: Self, array_list: *std.array_list.Managed(u8), needle: []const u8, max_size: usize) ![]u8 {
            const initial_len = array_list.items.len;
            for (0..max_size) |i| {
                try array_list.append(try readByte(self));
                if (std.mem.endsWith(u8, array_list.items, needle)) return array_list.items[initial_len..][0 .. i + 1 - needle.len];
            }
            return error.StreamTooLong;
        }

        pub fn readAlloc(self: Self, allocator: std.mem.Allocator, size: usize) ![]u8 {
            var array_list = try std.array_list.Managed(u8).initCapacity(allocator, size);
            defer array_list.deinit();
            try array_list.ensureUnusedCapacity(size);
            const len = try readAll(self, array_list.allocatedSlice());
            array_list.items.len += len;
            if (len != size) return error.EndOfStream;
            return array_list.toOwnedSlice();
        }

        pub fn readInt(self: Self, I: type, endian: std.builtin.Endian) !I {
            comptime std.debug.assert(@bitSizeOf(I) % 8 == 0);
            const array = try readArray(self, @sizeOf(I));
            return std.mem.readInt(I, &array, endian);
        }

        /// Returned slice is suffixed by needle.
        pub fn readUntilDelimitersAlloc(self: Self, allocator: std.mem.Allocator, needle: []const u8, max_size: usize) ![]u8 {
            var list: std.array_list.Managed(u8) = .init(allocator);
            errdefer list.deinit();
            _ = try readUntilDelimitersArrayList(self, &list, needle, max_size);
            return list.toOwnedSlice();
        }

        pub fn readUntilDelimiter(self: Self, buf: []u8, needle: u8) ![]u8 {
            for (buf, 0..) |*c, i| {
                const b = try readByte(self);
                c.* = b;
                if (b == needle) return buf[0..i];
            }
            return error.StreamTooLong;
        }

        /// Returned slice is not suffixed by needle but buf will contain it.
        pub fn readUntilDelimiterOrEof(self: Self, buf: []u8, needle: u8) !?[]u8 {
            for (buf, 0..) |*c, i| {
                const b = try readByte(self);
                c.* = b;
                if (b == needle) {
                    if (i == 0) return null;
                    return buf[0..i];
                }
            }
            return error.StreamTooLong;
        }

        pub fn readExpected(self: Self, expected: []const u8) !bool {
            for (expected) |item| {
                const actual = try readByte(self);
                if (actual != item) {
                    return false;
                }
            }
            return true;
        }

        pub fn skipBytes(self: Self, num_bytes: u64, comptime options: struct { buf_size: usize = 512 }) anyerror!void {
            var buf: [options.buf_size]u8 = undefined;
            var remaining = num_bytes;
            while (remaining > 0) {
                const amt = @min(remaining, options.buf_size);
                try readNoEof(self, buf[0..amt]);
                remaining -= amt;
            }
        }

        pub fn skipUntilDelimiterOrEof(self: Self, delimiter: u8) anyerror!void {
            while (true) {
                const byte = self.readByte() catch |err| switch (err) {
                    error.EndOfStream => return,
                    else => |e| return e,
                };
                if (byte == delimiter) return;
            }
        }
    };
}

pub fn Writable(T: type, this_kind: enum { _var, _const, _bare }) type {
    return struct {
        const Error = T.WriteError;

        const Self = switch (this_kind) {
            ._var => *T,
            ._const => *const T,
            ._bare => T,
        };

        // pub fn write(self: Self, bytes: []const u8) WriteError!usize {
        // }

        // pub fn writev(self: Self, iovec: []const sys.struct_iovec) WriteError!usize {
        // }

        pub fn writeAll(self: Self, bytes: []const u8) Error!void {
            var index: usize = 0;
            while (index != bytes.len) {
                index += try self.write(bytes[index..]);
            }
        }

        pub fn writevAll(self: Self, bytes: []const []const u8) Error!void {
            var iovec: [1024]sys.struct_iovec = undefined;
            for (bytes, 0..) |slice, i| iovec[i] = .{ .base = @constCast(slice.ptr), .len = slice.len };
            var left: usize = 0;
            for (bytes) |item| left += item.len;

            while (left > 0) {
                var written: usize = try self.writev(iovec[0..bytes.len]);
                left -= written;
                for (iovec[0..bytes.len], 0..) |vec, i| {
                    switch (std.math.order(written, vec.len)) {
                        .gt => {
                            written -= iovec[i].len;
                            iovec[i].len = 0;
                            continue;
                        },
                        .eq => {
                            written -= iovec[i].len;
                            iovec[i].len = 0;
                            break;
                        },
                        .lt => {
                            iovec[i].base += written;
                            iovec[i].len -= written;
                            written -= written;
                        },
                    }
                }
                std.debug.assert(written == 0);
            }
        }

        pub fn writeByteNTimes(self: Self, byte: u8, n: usize) Error!void {
            var bytes: [1024]u8 = undefined;
            @memset(bytes[0..], byte);
            var remaining: usize = n;
            while (remaining > 0) {
                const to_write = @min(remaining, bytes.len);
                try writeAll(self, bytes[0..to_write]);
                remaining -= to_write;
            }
        }

        pub fn writeNTimes(self: Self, input: []const u8, n: usize) Error!void {
            var bytes: [1024][]const u8 = @splat(input);
            var remaining: usize = n;
            while (remaining > 0) {
                const to_write = @min(remaining, bytes.len);
                try writevAll(self, bytes[0..n]);
                remaining -= to_write;
            }
        }

        pub fn writeInt(self: Self, comptime I: type, value: I, endian: std.builtin.Endian) Error!void {
            var bytes: [@as(u16, @intCast((@as(u17, @typeInfo(I).int.bits) + 7) / 8))]u8 = undefined;
            std.mem.writeInt(std.math.ByteAlignedInt(I), &bytes, value, endian);
            return writeAll(self, &bytes);
        }

        pub fn writeStruct(self: Self, value: anytype) Error!void {
            // Only extern and packed structs have defined in-memory layout.
            comptime std.debug.assert(@typeInfo(@TypeOf(value)).@"struct".layout != .auto);
            return writeAll(self, std.mem.asBytes(&value));
        }

        pub fn writeIntPretty(self: Self, value: anytype, base: u8, case: fmt.Case) !void {
            std.debug.assert(base >= 2);

            const int_value = if (@TypeOf(value) == comptime_int) @as(std.math.IntFittingRange(value, value), value) else value;
            const value_info = @typeInfo(@TypeOf(int_value)).int;

            // The type must have the same size as `base` or be wider in order for the division to work
            const min_int_bits = comptime @max(value_info.bits, 8);
            const MinInt = std.meta.Int(.unsigned, min_int_bits);

            const abs_value = @abs(int_value);
            // The worst case in terms of space needed is base 2, plus 1 for the sign
            var buf: [1 + @max(@as(comptime_int, value_info.bits), 1)]u8 = undefined;

            var a: MinInt = abs_value;
            var index: usize = buf.len;

            if (base == 10) {
                while (a >= 100) : (a = @divTrunc(a, 100)) {
                    index -= 2;
                    buf[index..][0..2].* = fmt.digits2(@intCast(a % 100));
                }
                if (a < 10) {
                    index -= 1;
                    buf[index] = '0' + @as(u8, @intCast(a));
                } else {
                    index -= 2;
                    buf[index..][0..2].* = fmt.digits2(@intCast(a));
                }
            } else {
                while (true) {
                    const digit = a % base;
                    index -= 1;
                    buf[index] = fmt.digitToChar(@intCast(digit), case);
                    a /= base;
                    if (a == 0) break;
                }
            }

            if (value_info.signedness == .signed) {
                if (value < 0) {
                    // Negative integer
                    index -= 1;
                    buf[index] = '-';
                } else if (true) {
                    // Positive integer, omit the plus sign
                    // if (options.width == null or options.width.? == 0)
                } else {
                    // Positive integer
                    index -= 1;
                    buf[index] = '+';
                }
            }

            return writeAll(self, buf[index..]);
        }

        pub fn print(self: Self, comptime format: []const u8, args: anytype) Error!void {
            return fmt.format(self, format, args);
        }
    };
}

pub const AnyReadable = @import("./AnyReadable.zig");

pub const AnyWritable = @import("./AnyWritable.zig");

pub const FixedBufferStream = @import("./fixed_buffer_stream.zig").FixedBufferStream;

pub const BufferedReader = @import("./buffered_reader.zig").BufferedReader;

pub const BufferedWriter = @import("./buffered_writer.zig").BufferedWriter;

pub const CountingWriter = @import("./counting_writer.zig").CountingWriter;

pub const NullWriter = @import("./null_writer.zig").NullWriter;

pub const AllocatingWriter = @import("./allocating_writer.zig").AllocatingWriter;

pub const CountingReader = @import("./counting_reader.zig").CountingReader;

pub const LimitedReader = @import("./limited_reader.zig").LimitedReader;
