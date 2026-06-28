const std = @import("std");
const nio = @import("./nio.zig");
const builtin = @import("builtin");

const sys = switch (builtin.target.os.tag) {
    .linux => @import("sys-linux"),
    .macos => @import("sys-darwin"),
    else => unreachable,
};

pub const AllocatingWriter = struct {
    allocator: std.mem.Allocator,
    items: []u8,
    capacity: usize,

    pub fn init(allocator: std.mem.Allocator) AllocatingWriter {
        return .{
            .allocator = allocator,
            .items = "",
            .capacity = 0,
        };
    }

    pub fn deinit(self: *AllocatingWriter) void {
        self.allocator.free(self.allocatedSlice());
    }

    pub fn allocatedSlice(self: *AllocatingWriter) []u8 {
        return self.items.ptr[0..self.capacity];
    }

    pub fn toOwnedSlice(self: *AllocatingWriter) ![]u8 {
        if (self.allocator.resize(self.allocatedSlice(), self.items.len)) {
            defer self.capacity = 0;
            defer self.items = "";
            return self.items;
        }
        const new_slice = try self.allocator.dupe(u8, self.items);
        self.allocator.free(self.allocatedSlice());
        return new_slice;
    }

    pub fn ensureUnusedCapacity(self: *AllocatingWriter, capacity: usize) !void {
        if (self.capacity - self.items.len >= capacity) return;
        const len = self.items.len;
        const new_capacity = std.math.ceilPowerOfTwo(usize, @max(len + capacity, self.capacity)) catch return error.OutOfMemory;
        const new_slice = try self.allocator.alloc(u8, new_capacity);
        @memcpy(new_slice[0..len], self.items);
        self.allocator.free(self.allocatedSlice());
        self.items = new_slice;
        self.items.len = len;
        self.capacity = new_capacity;
    }

    pub fn unusedSlice(self: *AllocatingWriter) []u8 {
        return self.allocatedSlice()[self.items.len..];
    }

    pub fn appendAssumeCapacity(self: *AllocatingWriter, bytes: []const u8) void {
        @memcpy(self.unusedSlice()[0..bytes.len], bytes);
        self.items.len += bytes.len;
    }

    pub fn orderedRemove(self: *AllocatingWriter, index: usize) u8 {
        const old_item = self.items[index];
        std.mem.copyForwards(u8, self.items[index .. self.items.len - 1], self.items[index + 1 .. self.items.len]);
        self.items.len -= 1;
        return old_item;
    }

    pub fn last(self: *AllocatingWriter) u8 {
        return self.items[self.items.len - 1];
    }

    pub fn insertAt(self: *AllocatingWriter, index: usize, bytes: []const u8) !void {
        try self.ensureUnusedCapacity(bytes.len);
        self.items.len += bytes.len;
        std.mem.copyBackwards(u8, self.items[index + bytes.len .. self.items.len], self.items[index .. self.items.len - bytes.len]);
        @memcpy(self.items[index..][0..bytes.len], bytes);
    }

    pub fn clearAndFree(self: *AllocatingWriter) void {
        self.allocator.free(self.allocatedSlice());
        self.items.len = 0;
        self.capacity = 0;
    }

    pub fn replaceRangeAssumeCapacity(self: *AllocatingWriter, start: usize, len: usize, new_items: []const u8) void {
        std.debug.assert(self.capacity - self.items.len >= new_items.len -| len);
        const tail = self.items[start + len ..];
        const vacated = self.items[self.items.len - (len -| new_items.len) ..];
        self.items.len = self.items.len - len + new_items.len;
        @memmove(self.items[start + new_items.len ..], tail);
        @memcpy(self.items[start..][0..new_items.len], new_items);
        @memset(vacated, undefined);
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

    pub const WriteError = std.mem.Allocator.Error;

    pub fn write(self: *AllocatingWriter, bytes: []const u8) WriteError!usize {
        try self.ensureUnusedCapacity(bytes.len);
        self.appendAssumeCapacity(bytes);
        return bytes.len;
    }
    pub fn writev(self: *AllocatingWriter, iovec: []const sys.struct_iovec) WriteError!usize {
        var len: usize = 0;
        for (iovec) |vec| len += vec.len;
        try self.ensureUnusedCapacity(len);
        for (iovec) |vec| self.appendAssumeCapacity(vec.base[0..vec.len]);
        return len;
    }

    pub fn anyWritable(self: *AllocatingWriter) nio.AnyWritable {
        const S = struct {
            fn write(s: *allowzero anyopaque, buffer: []const u8) anyerror!usize {
                const bw: *AllocatingWriter = @ptrCast(@alignCast(s));
                return bw.write(buffer);
            }
        };
        return .{
            .vtable = &.{ .write = S.write },
            .state = @ptrCast(self),
        };
    }
};
