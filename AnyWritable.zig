const std = @import("std");
const builtin = @import("builtin");
const sys_linux = @import("sys-linux");

const sys = switch (builtin.target.os.tag) {
    .linux => sys_linux,
    else => unreachable,
};

const nio = @import("./nio.zig");
const AnyWritable = @This();

vtable: *const struct {
    write: *const fn (*allowzero anyopaque, []const u8) anyerror!usize,
},
state: *allowzero anyopaque,

const W = nio.Writable(@This(), ._const);
pub const writeAll = W.writeAll;
pub const writevAll = W.writevAll;
pub const writeByteNTimes = W.writeByteNTimes;
pub const writeNTimes = W.writeNTimes;
pub const writeInt = W.writeInt;
pub const writeStruct = W.writeStruct;
pub const writeIntPretty = W.writeIntPretty;
pub const print = W.print;

pub const WriteError = anyerror;
pub fn write(r: AnyWritable, buffer: []const u8) !usize {
    return r.vtable.write(r.state, buffer);
}
pub fn writev(w: AnyWritable, iovec: []const sys.struct_iovec) WriteError!usize {
    var total: usize = 0;
    for (iovec) |vec| {
        const len = try write(w, vec.base[0..vec.len]);
        total += len;
        if (len != vec.len) break;
    }
    return total;
}
pub fn anyWritable(r: AnyWritable) AnyWritable {
    return r;
}

pub fn fromStd(writer_ptr: *std.Io.Writer) AnyWritable {
    const S = struct {
        fn _write(s: *allowzero anyopaque, buffer: []const u8) !usize {
            const r: @TypeOf(writer_ptr) = @ptrCast(@alignCast(s));
            return r.write(buffer);
        }
    };
    return .{
        .vtable = &.{ .write = &S._write },
        .state = @ptrCast(@constCast(writer_ptr)),
    };
}

pub fn toStd(r: AnyWritable, buf: []u8) StdWriter {
    const S = struct {
        fn drain(sw: *std.Io.Writer, data: []const []const u8, splat: usize) error{WriteFailed}!usize {
            const w: *StdWriter = @alignCast(@fieldParentPtr("sw", sw));
            while (true) {
                const rem = w.sw.buffered();
                const n = w.aw.write(rem) catch return error.WriteFailed;
                const l = w.sw.consume(n);
                if (l == 0) break;
            }
            var n: usize = 0;
            const slice = data[0 .. data.len - 1];
            w.aw.writevAll(slice) catch return error.WriteFailed;
            for (slice) |x| n += x.len;
            const pattern = data[slice.len];
            w.aw.writeNTimes(pattern, splat) catch return error.WriteFailed;
            n += pattern.len * splat;
            return n;
        }
        fn flush(sw: *std.Io.Writer) error{WriteFailed}!void {
            const w: *StdWriter = @alignCast(@fieldParentPtr("sw", sw));
            return w.aw.writeAll(w.sw.buffered()) catch return error.WriteFailed;
        }
    };
    return .{
        .aw = r,
        .sw = .{
            .vtable = &.{
                .drain = S.drain,
                .flush = S.flush,
            },
            .buffer = buf,
        },
    };
}
const StdWriter = struct {
    aw: AnyWritable,
    sw: std.Io.Writer,
};
