const std = @import("std");
const nio = @import("nio");
const expect = @import("expect").expect;

test {
    for (&[_][2][]const u8{
        .{ "", "" },
        .{ "f", "Zg==" },
        .{ "fo", "Zm8=" },
        .{ "foo", "Zm9v" },
        .{ "foob", "Zm9vYg==" },
        .{ "fooba", "Zm9vYmE=" },
        .{ "foobar", "Zm9vYmFy" },
    }) |case| {
        const input, const expected = case;
        const allocator = std.testing.allocator;
        var aw = nio.AllocatingWriter.init(allocator);
        defer aw.deinit();
        var bw = nio.Base64Writer(void).from(&aw, .standard);
        try bw.writeAll(input);
        try bw.flush(.yes_pad);
        try expect(aw.items).toEqualString(expected);
    }
}
