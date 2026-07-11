const std = @import("std");
const builtin = @import("builtin");
const extras = @import("extras");
const nio = @import("./nio.zig");
const standard_alphabet_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
const url_safe_alphabet_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".*;

pub fn Base64Reader(comptime ReaderType: type) type {
    return struct {
        source_reader: ReaderType,
        alphabet: *const [64]u8,
        bits: std.bit_set.IntegerBitSet(bit_max),
        jdx: u8,

        const Self = @This();
        const bit_max = std.math.log2(64); // 6

        pub fn init(source_reader: ReaderType) Self {
            return .{
                .source_reader = source_reader,
                .alphabet = standard_alphabet_chars,
                .bits = .empty,
                .jdx = bit_max,
            };
        }

        pub fn from(source_reader: anytype) Base64Reader(@TypeOf(source_reader)) {
            return .init(source_reader);
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

        pub const ReadError = extras.Pointee(ReaderType).ReadError || error{InvalidCharacter};
        pub fn read(self: *Self, dest: []u8) ReadError!usize {
            var i: usize = 0;
            while (i < dest.len) {
                dest[i] = self.nextInt(u8) catch |err| switch (err) {
                    error.EndOfStream => break,
                    else => |e| return e,
                };
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

        pub fn next(self: *Self) !u1 {
            if (self.jdx == bit_max) {
                const c = try self.source_reader.readByte();
                self.bits.mask = @intCast(std.mem.findScalar(u8, self.alphabet, c) orelse if (c == '=') 0 else return error.InvalidCharacter);
                self.jdx = 0;
                return self.next();
            }
            defer self.jdx += 1;
            return @intFromBool(self.bits.isSet(bit_max - 1 - self.jdx));
        }

        pub fn nextInt(self: *Self, T: type) !T {
            const info = @typeInfo(T).int;
            var result: T = 0;
            for (0..info.bits) |_| {
                result <<= 1;
                const val = try self.next();
                result += val;
            }
            return result;
        }
    };
}
