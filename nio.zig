const std = @import("std");

pub fn Readable(T: type) type {
    return struct {
        const Error = T.ReadError;

        /// Returns the number of bytes read. It may be less than buffer.len.
        /// If the number of bytes read is 0, it means end of stream.
        /// End of stream is not an error condition.
        // pub fn read(self: *T, buffer: []u8) Error!usize {
        // }

        /// Returns the number of bytes read. If the number read is smaller than `buffer.len`, it
        /// means the stream reached the end. Reaching the end of a stream is not an error
        /// condition.
        pub fn readAll(self: *T, buffer: []u8) Error!usize {
            return self.readAtLeast(buffer, buffer.len);
        }

        /// Returns the number of bytes read, calling the underlying read
        /// function the minimal number of times until the buffer has at least
        /// `len` bytes filled. If the number read is less than `len` it means
        /// the stream reached the end. Reaching the end of the stream is not
        /// an error condition.
        pub fn readAtLeast(self: *T, buffer: []u8, len: usize) Error!usize {
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
        pub fn readNoEof(self: *T, buf: []u8) (Error || error{EndOfStream})!void {
            const amt_read = try self.readAll(buf);
            if (amt_read < buf.len) return error.EndOfStream;
        }
    };
}

pub const AnyReadable = @import("./AnyReadable.zig");

pub const FixedBufferStream = @import("./fixed_buffer_stream.zig").FixedBufferStream;
