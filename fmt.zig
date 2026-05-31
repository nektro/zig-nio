//! String formatting and parsing.

const std = @import("std");
const builtin = @import("builtin");
const extras = @import("extras");
const nio = @import("./nio.zig");

/// Renders fmt string with args, calling `writer` with slices of bytes.
/// If `writer` returns an error, the error is returned from `format` and
/// `writer` is not called again.
///
/// The format string must be comptime-known and may contain placeholders following
/// this format:
/// `{[argument][specifier]:[fill][alignment][width].[precision]}`
///
/// Above, each word including its surrounding [ and ] is a parameter which you have to replace with something:
///
/// - *argument* is either the numeric index or the field name of the argument that should be inserted
///   - when using a field name, you are required to enclose the field name (an identifier) in square
///     brackets, e.g. {[score]...} as opposed to the numeric index form which can be written e.g. {2...}
/// - *specifier* is a type-dependent formatting option that determines how a type should formatted (see below)
/// - *fill* is a single unicode codepoint which is used to pad the formatted text
/// - *alignment* is one of the three bytes '<', '^', or '>' to make the text left-, center-, or right-aligned, respectively
/// - *width* is the total width of the field in unicode codepoints
/// - *precision* specifies how many decimals a formatted number should have
///
/// Note that most of the parameters are optional and may be omitted. Also you can leave out separators like `:` and `.` when
/// all parameters after the separator are omitted.
/// Only exception is the *fill* parameter. If a non-zero *fill* character is required at the same time as *width* is specified,
/// one has to specify *alignment* as well, as otherwise the digit following `:` is interpreted as *width*, not *fill*.
///
/// The *specifier* has several options for types:
/// - `x` and `X`: output numeric value in hexadecimal notation
/// - `s`:
///   - for pointer-to-many and C pointers of u8, print as a C-string using zero-termination
///   - for slices of u8, print the entire slice as a string without zero-termination
/// - `e`: output floating point value in scientific notation
/// - `d`: output numeric value in decimal notation
/// - `b`: output integer value in binary notation
/// - `o`: output integer value in octal notation
/// - `c`: output integer as an ASCII character. Integer type must have 8 bits at max.
/// - `u`: output integer as an UTF-8 sequence. Integer type must have 21 bits at max.
/// - `?`: output optional value as either the unwrapped value, or `null`; may be followed by a format specifier for the underlying value.
/// - `!`: output error union value as either the unwrapped value, or the formatted error value; may be followed by a format specifier for the underlying value.
/// - `*`: output the address of the value instead of the value itself.
/// - `any`: output a value of any type using its default format.
///
/// If a formatted user type contains a function of the type
/// ```
///  fn format(value: ?, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void
/// ```
/// with `?` being the type formatted, this function will be called instead of the default implementation.
/// This allows user types to be formatted in a logical manner instead of dumping all fields of the type.
///
/// A user type may be a `struct`, `vector`, `union` or `enum` type.
///
/// To print literal curly braces, escape them by writing them twice, e.g. `{{` or `}}`.
pub fn format(writer: anytype, comptime fmt: []const u8, args: anytype) !void {
    const ArgsType = @TypeOf(args);
    const args_type_info = @typeInfo(ArgsType);
    if (args_type_info != .@"struct") {
        @compileError("expected tuple or struct argument, found " ++ @typeName(ArgsType));
    }

    const fields_info = args_type_info.@"struct".fields;
    if (fields_info.len > max_format_args) {
        @compileError("32 arguments max are supported per format call");
    }

    @setEvalBranchQuota(std.math.maxInt(u32));
    comptime var arg_state: ArgState = .{ .args_len = fields_info.len };
    comptime var i = 0;
    comptime var literal: []const u8 = "";
    inline while (true) {
        const start_index = i;

        inline while (i < fmt.len) : (i += 1) {
            switch (fmt[i]) {
                '{', '}' => break,
                else => {},
            }
        }

        comptime var end_index = i;
        comptime var unescape_brace = false;

        // Handle {{ and }}, those are un-escaped as single braces
        if (i + 1 < fmt.len and fmt[i + 1] == fmt[i]) {
            unescape_brace = true;
            // Make the first brace part of the literal...
            end_index += 1;
            // ...and skip both
            i += 2;
        }

        literal = literal ++ fmt[start_index..end_index];

        // We've already skipped the other brace, restart the loop
        if (unescape_brace) continue;

        // Write out the literal
        if (literal.len != 0) {
            try writer.writeAll(literal);
            literal = "";
        }

        if (i >= fmt.len) break;

        if (fmt[i] == '}') {
            @compileError("missing opening {");
        }

        // Get past the {
        comptime std.debug.assert(fmt[i] == '{');
        i += 1;

        const fmt_begin = i;
        // Find the closing brace
        inline while (i < fmt.len and fmt[i] != '}') : (i += 1) {}
        const fmt_end = i;

        if (i >= fmt.len) {
            @compileError("missing closing }");
        }

        // Get past the }
        comptime std.debug.assert(fmt[i] == '}');
        i += 1;

        const placeholder = comptime Placeholder.parse(fmt[fmt_begin..fmt_end].*);
        const arg_pos = comptime switch (placeholder.arg) {
            .none => null,
            .number => |pos| pos,
            .named => |arg_name| std.meta.fieldIndex(ArgsType, arg_name) orelse @compileError("no argument with name '" ++ arg_name ++ "'"),
        };

        const width = switch (placeholder.width) {
            .none => null,
            .number => |v| v,
            .named => |arg_name| blk: {
                const arg_i = comptime std.meta.fieldIndex(ArgsType, arg_name) orelse @compileError("no argument with name '" ++ arg_name ++ "'");
                _ = comptime arg_state.nextArg(arg_i) orelse @compileError("too few arguments");
                break :blk @field(args, arg_name);
            },
        };

        const precision = switch (placeholder.precision) {
            .none => null,
            .number => |v| v,
            .named => |arg_name| blk: {
                const arg_i = comptime std.meta.fieldIndex(ArgsType, arg_name) orelse @compileError("no argument with name '" ++ arg_name ++ "'");
                _ = comptime arg_state.nextArg(arg_i) orelse @compileError("too few arguments");
                break :blk @field(args, arg_name);
            },
        };

        const arg_to_print = comptime arg_state.nextArg(arg_pos) orelse @compileError("too few arguments");

        try formatType(
            @field(args, fields_info[arg_to_print].name),
            placeholder.specifier_arg,
            .{
                .fill = placeholder.fill,
                .alignment = placeholder.alignment,
                .width = width,
                .precision = precision,
            },
            writer,
            std.options.fmt_max_depth,
        );
    }

    if (comptime arg_state.hasUnusedArgs()) {
        const missing_count = arg_state.args_len - @popCount(arg_state.used_args);
        switch (missing_count) {
            0 => unreachable,
            1 => @compileError("unused argument in '" ++ fmt ++ "'"),
            else => @compileError(comptimePrint("{d}", .{missing_count}) ++ " unused arguments in '" ++ fmt ++ "'"),
        }
    }
}

pub const FormatOptions = struct {
    precision: ?usize = null,
    width: ?usize = null,
    alignment: Alignment = default_alignment,
    fill: u21 = default_fill_char,
};

pub const Alignment = enum { left, center, right };
pub const Case = enum { lower, upper };

const default_max_depth = 3;
const default_alignment = .right;
const default_fill_char = ' ';

const ArgSetType = u32;
const max_format_args = @typeInfo(ArgSetType).int.bits;

pub const ArgState = struct {
    next_arg: usize = 0,
    used_args: ArgSetType = 0,
    args_len: usize,

    fn hasUnusedArgs(self: *@This()) bool {
        return @popCount(self.used_args) != self.args_len;
    }

    fn nextArg(self: *@This(), arg_index: ?usize) ?usize {
        const next_index = arg_index orelse init: {
            const arg = self.next_arg;
            self.next_arg += 1;
            break :init arg;
        };

        if (next_index >= self.args_len) {
            return null;
        }

        // Mark this argument as used
        self.used_args |= @as(ArgSetType, 1) << @as(u5, @intCast(next_index));
        return next_index;
    }
};

pub const Placeholder = struct {
    specifier_arg: []const u8,
    fill: u21,
    alignment: Alignment,
    arg: Specifier,
    width: Specifier,
    precision: Specifier,

    fn parse(comptime str: anytype) Placeholder {
        const view = std.unicode.Utf8View.initComptime(&str);
        comptime var parser = Parser{
            .iter = view.iterator(),
        };

        // Parse the positional argument number
        const arg = comptime parser.specifier() catch |err| @compileError(@errorName(err));

        // Parse the format specifier
        const specifier_arg = comptime parser.until(':');

        // Skip the colon, if present
        if (comptime parser.char()) |ch| {
            if (ch != ':') {
                @compileError("expected : or }, found '" ++ std.unicode.utf8EncodeComptime(ch) ++ "'");
            }
        }

        // Parse the fill character, if present.
        // When the width field is also specified, the fill character must
        // be followed by an alignment specifier, unless it's '0' (zero)
        // (in which case it's handled as part of the width specifier)
        var fill: ?u21 = comptime if (parser.peek(1)) |ch|
            switch (ch) {
                '<', '^', '>' => parser.char(),
                else => null,
            }
        else
            null;

        // Parse the alignment parameter
        const alignment: ?Alignment = comptime if (parser.peek(0)) |ch| init: {
            switch (ch) {
                '<', '^', '>' => {
                    // consume the character
                    break :init switch (parser.char().?) {
                        '<' => .left,
                        '^' => .center,
                        else => .right,
                    };
                },
                else => break :init null,
            }
        } else null;

        // When none of the fill character and the alignment specifier have
        // been provided, check whether the width starts with a zero.
        if (fill == null and alignment == null) {
            fill = comptime if (parser.peek(0) == '0') '0' else null;
        }

        // Parse the width parameter
        const width = comptime parser.specifier() catch |err| @compileError(@errorName(err));

        // Skip the dot, if present
        if (comptime parser.char()) |ch| {
            if (ch != '.') {
                @compileError("expected . or }, found '" ++ std.unicode.utf8EncodeComptime(ch) ++ "'");
            }
        }

        // Parse the precision parameter
        const precision = comptime parser.specifier() catch |err| @compileError(@errorName(err));

        if (comptime parser.char()) |ch| {
            @compileError("extraneous trailing character '" ++ std.unicode.utf8EncodeComptime(ch) ++ "'");
        }

        return Placeholder{
            .specifier_arg = cacheString(specifier_arg[0..specifier_arg.len].*),
            .fill = fill orelse default_fill_char,
            .alignment = alignment orelse default_alignment,
            .arg = arg,
            .width = width,
            .precision = precision,
        };
    }
};

pub const Specifier = union(enum) {
    none,
    number: usize,
    named: []const u8,
};

/// A stream based parser for format strings.
///
/// Allows to implement formatters compatible with std.fmt without replicating
/// the standard library behavior.
pub const Parser = struct {
    iter: std.unicode.Utf8Iterator,

    // Returns a decimal number or null if the current character is not a
    // digit
    fn number(self: *@This()) ?usize {
        var r: ?usize = null;

        while (self.peek(0)) |code_point| {
            switch (code_point) {
                '0'...'9' => {
                    if (r == null) r = 0;
                    r.? *= 10;
                    r.? += code_point - '0';
                },
                else => break,
            }
            _ = self.iter.nextCodepoint();
        }

        return r;
    }

    // Returns a substring of the input starting from the current position
    // and ending where `ch` is found or until the end if not found
    fn until(self: *@This(), ch: u21) []const u8 {
        const start = self.iter.i;
        while (self.peek(0)) |code_point| {
            if (code_point == ch)
                break;
            _ = self.iter.nextCodepoint();
        }
        return self.iter.bytes[start..self.iter.i];
    }

    // Returns the character pointed to by the iterator if available, or
    // null otherwise
    fn char(self: *@This()) ?u21 {
        if (self.iter.nextCodepoint()) |code_point| {
            return code_point;
        }
        return null;
    }

    // Returns true if the iterator points to an existing character and
    // false otherwise
    fn maybe(self: *@This(), val: u21) bool {
        if (self.peek(0) == val) {
            _ = self.iter.nextCodepoint();
            return true;
        }
        return false;
    }

    // Returns a decimal number or null if the current character is not a
    // digit
    fn specifier(self: *@This()) !Specifier {
        if (self.maybe('[')) {
            const arg_name = self.until(']');

            if (!self.maybe(']'))
                return @field(anyerror, "Expected closing ]");

            return Specifier{ .named = arg_name };
        }
        if (self.number()) |i|
            return Specifier{ .number = i };

        return Specifier{ .none = {} };
    }

    // Returns the n-th next character or null if that's past the end
    fn peek(self: *@This(), n: usize) ?u21 {
        const original_i = self.iter.i;
        defer self.iter.i = original_i;

        var i: usize = 0;
        var code_point: ?u21 = null;
        while (i <= n) : (i += 1) {
            code_point = self.iter.nextCodepoint();
            if (code_point == null) return null;
        }
        return code_point;
    }
};

fn cacheString(str: anytype) []const u8 {
    return &str;
}

fn formatType(value: anytype, comptime fmt: []const u8, options: FormatOptions, writer: anytype, max_depth: usize) extras.Pointee(@TypeOf(writer)).WriteError!void {
    const T = @TypeOf(value);
    const actual_fmt = comptime if (std.mem.eql(u8, fmt, "any"))
        defaultSpec(T)
    else if (fmt.len != 0 and (fmt[0] == '?' or fmt[0] == '!')) switch (@typeInfo(T)) {
        .optional, .error_union => fmt,
        else => stripOptionalOrErrorUnionSpec(fmt),
    } else fmt;

    if (comptime std.mem.eql(u8, actual_fmt, "*")) {
        return formatAddress(value, options, writer);
    }

    if (comptime std.meta.hasMethod(T, "format")) {
        @compileError("fix this: " ++ @typeName(T));
    }
    if (std.meta.hasMethod(T, "nprint")) {
        return value.nprint(writer);
    }

    switch (@typeInfo(T)) {
        .comptime_int, .int, .comptime_float, .float => {
            return formatValue(value, actual_fmt, options, writer);
        },
        .void => {
            if (actual_fmt.len != 0) invalidFmtError(fmt, value);
            return formatBuf("void", options, writer);
        },
        .bool => {
            if (actual_fmt.len != 0) invalidFmtError(fmt, value);
            return formatBuf(if (value) "true" else "false", options, writer);
        },
        .optional => {
            if (actual_fmt.len == 0 or actual_fmt[0] != '?') @compileError("cannot format optional without a specifier (i.e. {?} or {any})");
            const remaining_fmt = comptime stripOptionalOrErrorUnionSpec(actual_fmt);
            if (value) |payload| {
                return formatType(payload, remaining_fmt, options, writer, max_depth);
            } else {
                return formatBuf("null", options, writer);
            }
        },
        .error_union => {
            if (actual_fmt.len == 0 or actual_fmt[0] != '!') @compileError("cannot format error union without a specifier (i.e. {!} or {any})");
            const remaining_fmt = comptime stripOptionalOrErrorUnionSpec(actual_fmt);
            if (value) |payload| {
                return formatType(payload, remaining_fmt, options, writer, max_depth);
            } else |err| {
                return formatType(err, "", options, writer, max_depth);
            }
        },
        .error_set => {
            if (actual_fmt.len != 0) invalidFmtError(fmt, value);
            try writer.writeAll("error.");
            return writer.writeAll(@errorName(value));
        },
        .@"enum" => |enumInfo| {
            if (comptime std.mem.eql(u8, actual_fmt, "d")) {
                try formatInt(@intFromEnum(value), 10, .lower, options, writer);
                return;
            }
            if (comptime std.mem.eql(u8, actual_fmt, "s") and enumInfo.is_exhaustive) {
                try writer.writeAll(@tagName(value));
                return;
            }
        },
        .@"union" => |info| {
            if (actual_fmt.len != 0) invalidFmtError(fmt, value);
            try writer.writeAll(@typeName(T));
            if (max_depth == 0) {
                return writer.writeAll("{ ... }");
            }
            if (info.tag_type) |UnionTagType| {
                try writer.writeAll("{ .");
                try writer.writeAll(@tagName(@as(UnionTagType, value)));
                try writer.writeAll(" = ");
                inline for (info.fields) |u_field| {
                    if (value == @field(UnionTagType, u_field.name)) {
                        try formatType(@field(value, u_field.name), "any", options, writer, max_depth - 1);
                    }
                }
                try writer.writeAll(" }");
            } else {
                try format(writer, "@{x}", .{@intFromPtr(&value)});
            }
        },
        .@"struct" => |info| {
            if (actual_fmt.len != 0) invalidFmtError(fmt, value);
            if (info.is_tuple) {
                // Skip the type and field names when formatting tuples.
                if (max_depth == 0) {
                    return writer.writeAll("{ ... }");
                }
                try writer.writeAll("{");
                inline for (info.fields, 0..) |f, i| {
                    if (i == 0) {
                        try writer.writeAll(" ");
                    } else {
                        try writer.writeAll(", ");
                    }
                    try formatType(@field(value, f.name), "any", options, writer, max_depth - 1);
                }
                return writer.writeAll(" }");
            }
            try writer.writeAll(@typeName(T));
            if (max_depth == 0) {
                return writer.writeAll("{ ... }");
            }
            try writer.writeAll("{");
            inline for (info.fields, 0..) |f, i| {
                if (i == 0) {
                    try writer.writeAll(" .");
                } else {
                    try writer.writeAll(", .");
                }
                try writer.writeAll(f.name);
                try writer.writeAll(" = ");
                try formatType(@field(value, f.name), "any", options, writer, max_depth - 1);
            }
            try writer.writeAll(" }");
        },
        .pointer => |ptr_info| switch (ptr_info.size) {
            .one => switch (@typeInfo(ptr_info.child)) {
                .array, .@"enum", .@"union", .@"struct" => {
                    return formatType(value.*, actual_fmt, options, writer, max_depth);
                },
                else => return format(writer, "{s}@{x}", .{ @typeName(ptr_info.child), @intFromPtr(value) }),
            },
            .many, .c => {
                if (actual_fmt.len == 0)
                    @compileError("cannot format pointer without a specifier (i.e. {s} or {*})");
                if (ptr_info.sentinel() != null) {
                    return formatType(std.mem.span(value), actual_fmt, options, writer, max_depth);
                }
                if (actual_fmt[0] == 's' and ptr_info.child == u8) {
                    return formatBuf(std.mem.span(value), options, writer);
                }
                invalidFmtError(fmt, value);
            },
            .slice => {
                if (actual_fmt.len == 0) {
                    @compileError("cannot format slice without a specifier (i.e. {s} or {any})");
                }
                if (max_depth == 0) {
                    return writer.writeAll("{ ... }");
                }
                if (actual_fmt[0] == 's' and ptr_info.child == u8) {
                    return formatBuf(value, options, writer);
                }
                try writer.writeAll("{ ");
                for (value, 0..) |elem, i| {
                    try formatType(elem, actual_fmt, options, writer, max_depth - 1);
                    if (i != value.len - 1) {
                        try writer.writeAll(", ");
                    }
                }
                try writer.writeAll(" }");
            },
        },
        .array => |info| {
            if (actual_fmt.len == 0) {
                @compileError("cannot format array without a specifier (i.e. {s} or {any})");
            }
            if (max_depth == 0) {
                return writer.writeAll("{ ... }");
            }
            if (actual_fmt[0] == 's' and info.child == u8) {
                return formatBuf(&value, options, writer);
            }
            try writer.writeAll("{ ");
            for (value, 0..) |elem, i| {
                try formatType(elem, actual_fmt, options, writer, max_depth - 1);
                if (i < value.len - 1) {
                    try writer.writeAll(", ");
                }
            }
            try writer.writeAll(" }");
        },
        .vector => |info| {
            if (max_depth == 0) {
                return writer.writeAll("{ ... }");
            }
            try writer.writeAll("{ ");
            var i: usize = 0;
            while (i < info.len) : (i += 1) {
                try formatType(value[i], actual_fmt, options, writer, max_depth - 1);
                if (i < info.len - 1) {
                    try writer.writeAll(", ");
                }
            }
            try writer.writeAll(" }");
        },
        .@"fn" => @compileError("unable to format function body type, use '*const " ++ @typeName(T) ++ "' for a function pointer type"),
        .type => {
            if (actual_fmt.len != 0) invalidFmtError(fmt, value);
            return formatBuf(@typeName(value), options, writer);
        },
        .enum_literal => {
            if (actual_fmt.len != 0) invalidFmtError(fmt, value);
            const buffer = [_]u8{'.'} ++ @tagName(value);
            return formatBuf(buffer, options, writer);
        },
        .null => {
            if (actual_fmt.len != 0) invalidFmtError(fmt, value);
            return formatBuf("null", options, writer);
        },
        else => @compileError("unable to format type '" ++ @typeName(T) ++ "'"),
    }
}

pub inline fn comptimePrint(comptime fmt: []const u8, args: anytype) *const [count(fmt, args):0]u8 {
    comptime {
        var buf: [count(fmt, args):0]u8 = undefined;
        _ = bufPrint(&buf, fmt, args) catch unreachable;
        buf[buf.len] = 0;
        const final = buf;
        return &final;
    }
}

fn defaultSpec(comptime T: type) [:0]const u8 {
    switch (@typeInfo(T)) {
        .array, .vector => return "any",
        .pointer => |ptr_info| switch (ptr_info.size) {
            .one => switch (@typeInfo(ptr_info.child)) {
                .array => return "any",
                else => {},
            },
            .many, .c => return "*",
            .slice => return "any",
        },
        .optional => |info| return "?" ++ defaultSpec(info.child),
        .error_union => |info| return "!" ++ defaultSpec(info.payload),
        else => {},
    }
    return "";
}

fn stripOptionalOrErrorUnionSpec(comptime fmt: []const u8) []const u8 {
    return if (std.mem.eql(u8, fmt[1..], "any"))
        "any"
    else
        fmt[1..];
}

fn formatAddress(value: anytype, options: FormatOptions, writer: anytype) @TypeOf(writer).Error!void {
    _ = options;
    const T = @TypeOf(value);

    switch (@typeInfo(T)) {
        .pointer => |info| {
            try writer.writeAll(@typeName(info.child) ++ "@");
            if (info.size == .slice)
                try formatInt(@intFromPtr(value.ptr), 16, .lower, FormatOptions{}, writer)
            else
                try formatInt(@intFromPtr(value), 16, .lower, FormatOptions{}, writer);
            return;
        },
        .optional => |info| {
            if (@typeInfo(info.child) == .pointer) {
                try writer.writeAll(@typeName(info.child) ++ "@");
                try formatInt(@intFromPtr(value), 16, .lower, FormatOptions{}, writer);
                return;
            }
        },
        else => {},
    }

    @compileError("cannot format non-pointer type " ++ @typeName(T) ++ " with * specifier");
}

pub fn formatInt(value: anytype, base: u8, case: Case, options: FormatOptions, writer: anytype) !void {
    std.debug.assert(base >= 2);

    const int_value = if (@TypeOf(value) == comptime_int) blk: {
        const Int = std.math.IntFittingRange(value, value);
        break :blk @as(Int, value);
    } else value;

    const value_info = @typeInfo(@TypeOf(int_value)).int;

    // The type must have the same size as `base` or be wider in order for the
    // division to work
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
            buf[index..][0..2].* = digits2(@intCast(a % 100));
        }

        if (a < 10) {
            index -= 1;
            buf[index] = '0' + @as(u8, @intCast(a));
        } else {
            index -= 2;
            buf[index..][0..2].* = digits2(@intCast(a));
        }
    } else {
        while (true) {
            const digit = a % base;
            index -= 1;
            buf[index] = digitToChar(@intCast(digit), case);
            a /= base;
            if (a == 0) break;
        }
    }

    if (value_info.signedness == .signed) {
        if (value < 0) {
            // Negative integer
            index -= 1;
            buf[index] = '-';
        } else if (options.width == null or options.width.? == 0) {
            // Positive integer, omit the plus sign
        } else {
            // Positive integer
            index -= 1;
            buf[index] = '+';
        }
    }

    return formatBuf(buf[index..], options, writer);
}

fn formatValue(value: anytype, comptime fmt: []const u8, options: FormatOptions, writer: anytype) !void {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .float, .comptime_float => return formatFloatValue(value, fmt, options, writer),
        .int, .comptime_int => return formatIntValue(value, fmt, options, writer),
        .bool => return formatBuf(if (value) "true" else "false", options, writer),
        else => comptime unreachable,
    }
}

fn invalidFmtError(comptime fmt: []const u8, value: anytype) void {
    @compileError("invalid format string '" ++ fmt ++ "' for type '" ++ @typeName(@TypeOf(value)) ++ "'");
}

fn formatBuf(buf: []const u8, options: FormatOptions, writer: anytype) !void {
    if (options.width) |min_width| {
        // In case of error assume the buffer content is ASCII-encoded
        const width = std.unicode.utf8CountCodepoints(buf) catch buf.len;
        const padding = if (width < min_width) min_width - width else 0;

        if (padding == 0) return writer.writeAll(buf);

        var fill_buffer: [4]u8 = undefined;
        const fill_utf8 = if (std.unicode.utf8Encode(options.fill, &fill_buffer)) |len|
            fill_buffer[0..len]
        else |err| switch (err) {
            error.Utf8CannotEncodeSurrogateHalf,
            error.CodepointTooLarge,
            => &std.unicode.utf8EncodeComptime(std.unicode.replacement_character),
        };
        switch (options.alignment) {
            .left => {
                try writer.writeAll(buf);
                try writer.writeNTimes(fill_utf8, padding);
            },
            .center => {
                const left_padding = padding / 2;
                const right_padding = (padding + 1) / 2;
                try writer.writeNTimes(fill_utf8, left_padding);
                try writer.writeAll(buf);
                try writer.writeNTimes(fill_utf8, right_padding);
            },
            .right => {
                try writer.writeNTimes(fill_utf8, padding);
                try writer.writeAll(buf);
            },
        }
    } else {
        // Fast path, avoid counting the number of codepoints
        try writer.writeAll(buf);
    }
}

/// Count the characters needed for format. Useful for preallocating memory
fn count(comptime fmt: []const u8, args: anytype) u64 {
    var counting_writer: nio.CountingWriter(nio.NullWriter) = .init(.{});
    format(&counting_writer, fmt, args) catch unreachable;
    return counting_writer.bytes_written;
}

/// Print a Formatter string into `buf`. Actually just a thin wrapper around `format` and `fixedBufferStream`.
/// Returns a slice of the bytes printed to.
pub fn bufPrint(buf: []u8, comptime fmt: []const u8, args: anytype) ![]u8 {
    var fbs: nio.FixedBufferStream([]u8) = .init(buf);
    format(&fbs, fmt, args) catch |err| switch (err) {
        error.NoSpaceLeft => return error.NoSpaceLeft,
        else => unreachable,
    };
    return fbs.written();
}
pub fn bufPrintZ(buf: []u8, comptime fmt: []const u8, args: anytype) ![:0]u8 {
    const result = try bufPrint(buf, fmt ++ "\x00", args);
    return result[0 .. result.len - 1 :0];
}

const digits2_alphabet = blk: {
    var data: [200]u8 = @splat(0);
    for (0..10) |m| {
        for (0..10) |n| {
            data[(m * 10 + n) * 2 + 0] = m + '0';
            data[(m * 10 + n) * 2 + 1] = n + '0';
        }
    }
    const result = data;
    break :blk result;
};

/// Converts values in the range [0, 100) to a base 10 string.
pub fn digits2(value: u8) [2]u8 {
    return digits2_alphabet[value * 2 ..][0..2].*;
}

pub fn digitToChar(digit: u8, case: Case) u8 {
    return switch (digit) {
        0...9 => digit + '0',
        10...35 => digit + (if (case == .upper) @as(u8, 'A') else @as(u8, 'a')) - 10,
        else => unreachable,
    };
}

fn formatIntValue(value: anytype, comptime fmt: []const u8, options: FormatOptions, writer: anytype) !void {
    comptime var base = 10;
    comptime var case: Case = .lower;

    const int_value = if (@TypeOf(value) == comptime_int) blk: {
        const Int = std.math.IntFittingRange(value, value);
        break :blk @as(Int, value);
    } else value;

    if (fmt.len == 0 or comptime std.mem.eql(u8, fmt, "d")) {
        base = 10;
        case = .lower;
    } else if (comptime std.mem.eql(u8, fmt, "c")) {
        if (@typeInfo(@TypeOf(int_value)).int.bits <= 8) {
            return formatAsciiChar(@as(u8, int_value), options, writer);
        } else {
            @compileError("cannot print integer that is larger than 8 bits as an ASCII character");
        }
    } else if (comptime std.mem.eql(u8, fmt, "u")) {
        if (@typeInfo(@TypeOf(int_value)).int.bits <= 21) {
            return formatUnicodeCodepoint(@as(u21, int_value), options, writer);
        } else {
            @compileError("cannot print integer that is larger than 21 bits as an UTF-8 sequence");
        }
    } else if (comptime std.mem.eql(u8, fmt, "b")) {
        base = 2;
        case = .lower;
    } else if (comptime std.mem.eql(u8, fmt, "x")) {
        base = 16;
        case = .lower;
    } else if (comptime std.mem.eql(u8, fmt, "X")) {
        base = 16;
        case = .upper;
    } else if (comptime std.mem.eql(u8, fmt, "o")) {
        base = 8;
        case = .lower;
    } else {
        invalidFmtError(fmt, value);
    }

    return formatInt(int_value, base, case, options, writer);
}

fn formatAsciiChar(c: u8, options: FormatOptions, writer: anytype) !void {
    return formatBuf(@as(*const [1]u8, &c), options, writer);
}

fn formatUnicodeCodepoint(c: u21, options: FormatOptions, writer: anytype) !void {
    var buf: [4]u8 = undefined;
    const len = std.unicode.utf8Encode(c, &buf) catch |err| switch (err) {
        error.Utf8CannotEncodeSurrogateHalf, error.CodepointTooLarge => {
            return formatBuf(&std.unicode.utf8EncodeComptime(std.unicode.replacement_character), options, writer);
        },
    };
    return formatBuf(buf[0..len], options, writer);
}

fn formatFloatValue(value: anytype, comptime fmt: []const u8, options: FormatOptions, writer: anytype) !void {
    var buf: [std.fmt.format_float.bufferSize(.decimal, f64)]u8 = undefined;

    if (fmt.len == 0 or comptime std.mem.eql(u8, fmt, "e")) {
        const s = std.fmt.formatFloat(&buf, value, .{ .mode = .scientific, .precision = options.precision }) catch |err| switch (err) {
            error.BufferTooSmall => "(float)",
        };
        return formatBuf(s, options, writer);
    } else if (comptime std.mem.eql(u8, fmt, "d")) {
        const s = std.fmt.formatFloat(&buf, value, .{ .mode = .decimal, .precision = options.precision }) catch |err| switch (err) {
            error.BufferTooSmall => "(float)",
        };
        return formatBuf(s, options, writer);
    } else if (comptime std.mem.eql(u8, fmt, "x")) {
        var buf_stream: nio.FixedBufferStream([]u8) = .init(&buf);
        std.fmt.formatFloatHexadecimal(value, options, &buf_stream) catch |err| switch (err) {
            error.NoSpaceLeft => unreachable,
        };
        return formatBuf(buf_stream.written(), options, writer);
    } else {
        invalidFmtError(fmt, value);
    }
}

pub fn allocPrint(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) ![]u8 {
    const size = std.math.cast(usize, count(fmt, args)) orelse return error.OutOfMemory;
    const buf = try allocator.alloc(u8, size);
    return bufPrint(buf, fmt, args) catch |err| switch (err) {
        error.NoSpaceLeft => unreachable, // we just counted the size above
    };
}
pub fn allocPrintZ(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) ![:0]u8 {
    const result = try allocPrint(allocator, fmt ++ "\x00", args);
    return result[0 .. result.len - 1 :0];
}
