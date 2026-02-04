const std = @import("std");

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
        fn readAllArrayList(self: Self, array_list: *std.ArrayList(u8), max_append_size: usize) !void {
            return readAllArrayListAligned(self, null, array_list, max_append_size);
        }

        fn readAllArrayListAligned(self: Self, comptime alignment: ?u29, array_list: *std.ArrayListAligned(u8, alignment), max_append_size: usize) !void {
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
            var array_list = std.ArrayList(u8).init(allocator);
            defer array_list.deinit();
            try readAllArrayList(self, &array_list, max_size);
            return try array_list.toOwnedSlice();
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

        // pub fn write(self: Self, bytes: []const u8) Error!usize {
        // }

        pub fn writeAll(self: Self, bytes: []const u8) Error!void {
            var index: usize = 0;
            while (index != bytes.len) {
                index += try self.write(bytes[index..]);
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

        pub fn writeInt(self: Self, comptime I: type, value: I, endian: std.builtin.Endian) Error!void {
            var bytes: [@as(u16, @intCast((@as(u17, @typeInfo(I).Int.bits) + 7) / 8))]u8 = undefined;
            std.mem.writeInt(std.math.ByteAlignedInt(I), &bytes, value, endian);
            return writeAll(self, &bytes);
        }

        pub fn writeStruct(self: Self, value: anytype) Error!void {
            // Only extern and packed structs have defined in-memory layout.
            comptime std.debug.assert(@typeInfo(@TypeOf(value)).Struct.layout != .Auto);
            return writeAll(self, std.mem.asBytes(&value));
        }
    };
}

pub const AnyReadable = @import("./AnyReadable.zig");

pub const AnyWritable = @import("./AnyWritable.zig");

pub const FixedBufferStream = @import("./fixed_buffer_stream.zig").FixedBufferStream;
