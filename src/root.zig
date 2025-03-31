const std = @import("std");
const Vec = std.ArrayList;
const mem = std.mem;
const Allocator = mem.Allocator;

pub const FromUtf8Error = struct {
    bytes: Vec(u8),
    err: Utf8Error,
};

pub const Utf8Error = struct {
    valid_up_to: usize,
    error_len: ?u8,
};

/// holds an internal pointer.
///
/// in other words, does not need to be stored behind a reference or pointer
/// like rust does.
///
/// Rust's `&str` is Zig's `str`.
pub const str = struct {
    inner: []const u8,

    const Self = @This();

    pub const StringResult = union(enum) {
        ok: Self,
        err: Utf8Error,
    };

    pub fn fromUtf8(v: []const u8) StringResult {
        const res = runUtf8Validation(v);
        switch (res) {
            .err => |err| {
                return .{ .err = err };
            },
            .ok => |_| {
                return .{ .ok = Self.fromUtf8Unchecked(v) };
            },
        }
    }

    pub fn fromUtf8Unchecked(v: []const u8) Self {
        return .{
            .inner = v,
        };
    }
};

// https://tools.ietf.org/html/rfc3629
const UTF8_CHAR_WIDTH: [256]u8 = .{
    // 1  2  3  4  5  6  7  8  9  A  B  C  D  E  F
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, // 0
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, // 1
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, // 2
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, // 3
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, // 4
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, // 5
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, // 6
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, // 7
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 8
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 9
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // A
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // B
    0, 0, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, // C
    2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, // D
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, // E
    4, 4, 4, 4, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // F
};

fn utf8CharWidth(b: u8) usize {
    return @intCast(UTF8_CHAR_WIDTH[@intCast(b)]);
}

const ValidationResult = union(enum) {
    err: Utf8Error,
    ok: void,
};

fn runUtf8Validation(v: []const u8) ValidationResult {
    var index: usize = 0;
    const len = v.len;

    const USIZE_BYTES: usize = @sizeOf(usize);

    const ascii_block_size = 2 * USIZE_BYTES;
    const blocks_end = blk: {
        if (len >= ascii_block_size) {
            break :blk len - ascii_block_size + 1;
        } else {
            break :blk 0;
        }
    };
    // Below, we safely fall back to a slower codepath if the offset is `MAX(usize)`,
    // so the end-to-end behavior is the same at compiletime and runtime.
    const _align = blk: {
        if (@inComptime()) {
            break :blk MAX(usize);
        } else {
            const ptr = v.ptr;
            const align_offset = mem.alignPointerOffset(ptr, USIZE_BYTES) orelse {
                @panic("something really fucking bad happened in `alignPointerOffset`.");
            };
            break :blk align_offset;
        }
    };

    while (index < len) {
        const old_offset = index;

        const first = v[index];
        if (first >= 128) {
            const w = utf8CharWidth(first);
            // 2-byte encoding is for codepoints  \u{0080} to  \u{07ff}
            //        first  C2 80        last DF BF
            // 3-byte encoding is for codepoints  \u{0800} to  \u{ffff}
            //        first  E0 A0 80     last EF BF BF
            //   excluding surrogates codepoints  \u{d800} to  \u{dfff}
            //               ED A0 80 to       ED BF BF
            // 4-byte encoding is for codepoints \u{10000} to \u{10ffff}
            //        first  F0 90 80 80  last F4 8F BF BF
            //
            // Use the UTF-8 syntax from the RFC
            //
            // https://tools.ietf.org/html/rfc3629
            // UTF8-1      = %x00-7F
            // UTF8-2      = %xC2-DF UTF8-tail
            // UTF8-3      = %xE0 %xA0-BF UTF8-tail / %xE1-EC 2( UTF8-tail ) /
            //               %xED %x80-9F UTF8-tail / %xEE-EF 2( UTF8-tail )
            // UTF8-4      = %xF0 %x90-BF 2( UTF8-tail ) / %xF1-F3 3( UTF8-tail ) /
            //               %xF4 %x80-8F 2( UTF8-tail )
            if (w == 2) {
                const nextval = blk: {
                    index += 1;
                    // we needed data, but there was none: error!
                    if (index >= len) {
                        return .{ .err = Utf8Error{ .valid_up_to = old_offset, .error_len = null } };
                    }
                    break :blk v[index];
                };

                if (@as(i8, @intCast(nextval)) >= -64) {
                    return .{ .err = Utf8Error{ .valid_up_to = old_offset, .error_len = 1 } };
                }
            } else if (w == 3) {
                {
                    const nextval = blk: {
                        index += 1;
                        // we needed data, but there was none: error!
                        if (index >= len) {
                            return .{ .err = Utf8Error{ .valid_up_to = old_offset, .error_len = null } };
                        }
                        break :blk v[index];
                    };

                    if ((first == 0xE0 and (nextval >= 0xA0 and nextval <= 0xBF)) or
                        ((first >= 0xE1 and first <= 0xEC) and (nextval >= 0x80 and nextval <= 0xBF)) or
                        (first == 0xED and (nextval >= 0x80 and nextval <= 0x9F)) or
                        ((first >= 0xEE and first <= 0xEF) and (nextval >= 0x80 and nextval <= 0xBF)))
                    {} else {
                        return .{ .err = Utf8Error{ .valid_up_to = old_offset, .error_len = 1 } };
                    }
                }

                const nextval = blk: {
                    index += 1;
                    // we needed data, but there was none: error!
                    if (index >= len) {
                        return .{ .err = Utf8Error{ .valid_up_to = old_offset, .error_len = null } };
                    }
                    break :blk v[index];
                };

                if (@as(i8, @intCast(nextval)) >= -64) {
                    return .{ .err = Utf8Error{ .valid_up_to = old_offset, .error_len = 2 } };
                }
            } else if (w == 4) {
                {
                    const nextval = blk: {
                        index += 1;
                        if (index >= len) {
                            return .{ .err = Utf8Error{ .valid_up_to = old_offset, .error_len = null } };
                        }
                        break :blk v[index];
                    };
                    if (!((first == 0xF0 and (nextval >= 0x90 and nextval <= 0xBF)) or
                        ((first >= 0xF1 and first <= 0xF3) and (nextval >= 0x80 and nextval <= 0xBF)) or
                        (first == 0xF4 and (nextval >= 0x80 and nextval <= 0x8F))))
                    {
                        return .{ .err = Utf8Error{ .valid_up_to = old_offset, .error_len = 1 } };
                    }
                }
                {
                    const nextval = blk: {
                        index += 1;
                        if (index >= len) {
                            return .{ .err = Utf8Error{ .valid_up_to = old_offset, .error_len = null } };
                        }
                        break :blk v[index];
                    };
                    if (@as(i8, @intCast(nextval)) >= -64) {
                        return .{ .err = Utf8Error{ .valid_up_to = old_offset, .error_len = 2 } };
                    }
                }
                {
                    const nextval = blk: {
                        index += 1;
                        if (index >= len) {
                            return .{ .err = Utf8Error{ .valid_up_to = old_offset, .error_len = null } };
                        }
                        break :blk v[index];
                    };
                    if (@as(i8, @intCast(nextval)) >= -64) {
                        return .{ .err = Utf8Error{ .valid_up_to = old_offset, .error_len = 3 } };
                    }
                }
            } else {
                return .{ .err = Utf8Error{ .valid_up_to = old_offset, .error_len = 1 } };
            }
        }
        index += 1;
    } else {
        // Ascii case, try to skip forward quickly.
        // When the pointer is aligned, read 2 words of data per iteration
        // until we find a word containing a non-ascii byte.
        if (_align != MAX(usize) and _align - index % USIZE_BYTES == 0) {
            const ptr = v.ptr;
            while (index < blocks_end) {
                // SAFETY: since `align - index` and `ascii_block_size` are
                // multiples of `USIZE_BYTES`, `block = ptr.add(index)` is
                // always aligned with a `usize` so it's safe to dereference
                // both `block` and `block.add(1)`.
                const block: *const usize = @alignCast(@ptrCast(ptr + index));
                const zu = containsNonascii(block.*);
                const zv = containsNonascii((@as([*]const u8, @ptrCast(block)) + 1)[0]);

                if (zu or zv) {
                    break;
                }
                index += ascii_block_size;
            }
            // step from the point where the wordwise loop stopped
            while (index < len and v[index] < 128) {
                index += 1;
            }
        } else {
            index += 1;
        }
    }
    return .{ .ok = {} };
}

fn usizeRepeat(x: u8) usize {
    const arrty = [@sizeOf(usize)]u8;
    const v: arrty = @splat(x);
    return @bitCast(v);
}

const NONASCII_MASK: usize = usizeRepeat(0x80);

inline fn containsNonascii(x: usize) bool {
    return (x & NONASCII_MASK) != 0;
}

inline fn MAX(comptime T: type) T {
    return @as(usize, @intCast(std.math.maxInt(usize)));
}

pub const char = struct {
    code: u32,

    const Self = @This();

    const TAG_CONT: u8 = 0b1000_0000;
    const TAG_TWO_B: u8 = 0b1100_0000;
    const TAG_THREE_B: u8 = 0b1110_0000;
    const TAG_FOUR_B: u8 = 0b1111_0000;

    const MAX_ONE_B: u32 = 0x80;
    const MAX_TWO_B: u32 = 0x800;
    const MAX_THREE_B: u32 = 0x10000;

    pub fn lenUtf8(self: Self) usize {
        return lenUtf8u32(self.code);
    }

    pub fn lenUtf8u32(code: u32) usize {
        if (code < MAX_ONE_B) return 1 //
        else if (code < MAX_TWO_B) return 2 //
        else if (code < MAX_THREE_B) return 3 //
        else return 4;
    }

    pub fn encodeUtf8(self: Self, buf: []u8) !str {
        const res = try encodeUtf8Raw(self.code, buf);
        return str.fromUtf8Unchecked(res);
    }

    pub fn encodeUtf8Raw(code: u32, dest: []u8) ![]u8 {
        const len = lenUtf8u32(code);

        if (len == 1) {
            if (dest.len < 1) return error.BufferNotBigEnough;
            dest[0] = @intCast(code);
        } else if (len == 2) {
            if (dest.len < 2) return error.BufferNotBigEnough;
            dest[0] = asCast(u8, code >> 6 & 0x1F) | TAG_TWO_B;
            dest[1] = asCast(u8, code & 0x3F) | TAG_CONT;
        } else if (len == 3) {
            if (dest.len < 3) return error.BufferNotBigEnough;
            dest[0] = asCast(u8, code >> 12 & 0x0F) | TAG_THREE_B;
            dest[1] = asCast(u8, code >> 6 & 0x3F) | TAG_CONT;
            dest[2] = asCast(u8, code & 0x3F) | TAG_CONT;
        } else if (len == 4) {
            if (dest.len < 3) return error.BufferNotBigEnough;
            dest[0] = asCast(u8, code >> 18 & 0x07) | TAG_FOUR_B;
            dest[1] = asCast(u8, code >> 12 & 0x3F) | TAG_CONT;
            dest[2] = asCast(u8, code >> 6 & 0x3F) | TAG_CONT;
            dest[3] = asCast(u8, code & 0x3F) | TAG_CONT;
        } else {
            if (@inComptime()) {
                @compileError("encodeUtf8: buffer does not have enough bytes to encode code point");
            } else {
                std.debug.panic("encodeUtf8: need {} bytes to encode {} but buffer has just {}", .{
                    len,
                    code,
                    dest.len,
                });
            }
        }
        return dest.ptr[0..len];
    }
};

inline fn asCast(comptime T: type, val: anytype) T {
    return @as(T, @intCast(val));
}

pub const String = struct {
    vec: Vec(u8),

    const Self = @This();
    const Slice = Vec(u8).Slice;

    pub fn eq(self: *const Self, other: *const Self) bool {
        return mem.eql(
            u8,
            self.vec.items,
            other.vec.items,
        );
    }

    /// Deinitialize with `deinit` or use `toOwnedSlice`.
    pub fn new(alloc: Allocator) Self {
        return .{
            .vec = Vec(u8).init(alloc),
        };
    }

    pub fn deinit(self: Self) void {
        self.vec.deinit();
    }

    pub fn toOwnedSlice(self: Self) Allocator.Error!Slice {
        return self.vec.toOwnedSlice();
    }

    /// Initialize with capacity to hold `num` elements.
    /// The resulting capacity will equal `num` exactly.
    /// Deinitialize with `deinit` or use `toOwnedSlice`.
    pub fn withCapacity(alloc: Allocator, capacity: usize) !Self {
        return .{
            .vec = try Vec(u8).initCapacity(alloc, capacity),
        };
    }

    pub fn fromUtf8(vec: Vec(u8)) FromUtf8Error!Self {
        const res = str.fromUtf8(&vec);
        if (res) {
            return Self{
                .vec = vec,
            };
        } else |err| {
            return FromUtf8Error{
                .bytes = vec,
                .err = err,
            };
        }
    }

    pub fn fromUtf8Unchecked(vec: Vec(u8)) Self {
        return Self{
            .vec = vec,
        };
    }

    pub fn asStr(self: *const Self) str {
        return str.fromUtf8Unchecked(self.vec.items);
    }

    pub fn pushStr(self: *Self, string: str) !void {
        try self.vec.appendSlice(string.inner);
    }

    pub fn push(self: *Self, ch: char) !void {
        if (ch.lenUtf8() == 1) {
            try self.vec.append(@intCast(ch.code));
        } else {
            var empty: [4]u8 = undefined;
            const char_bytes = try ch.encodeUtf8(&empty);
            try self.vec.appendSlice(char_bytes.inner);
        }
    }

    pub fn asBytes(self: *const Self) []const u8 {
        return self.vec.items;
    }

    pub fn reserve(self: *Self, additional: usize) !void {
        try self.vec.ensureTotalCapacity(self.vec.capacity + additional);
    }

    /// Deinitialize with `deinit` or use `toOwnedSlice`.
    pub fn fromStr(alloc: Allocator, s: str) !String {
        var string = Self.new(alloc);
        try string.vec.appendSlice(s.inner);
        return string;
    }

    // TODO: implement Cow<'_, str> in zig, and return Cow.borrowed wherever applicable.
    pub fn fromUtf8Lossy(alloc: Allocator, v: []u8) !String {
        var iter = Utf8Chunks.fromBytes(v);

        const first_valid = blk: {
            const chunk = iter.iterNext();
            if (chunk) |c| {
                const valid = c.valid;
                if (c.invalid.len == 0) {
                    std.debug.assert(valid.len == v.len);
                    return Self.fromStr(alloc, valid); // use Cow.borrowed when implemented
                }
                break :blk valid;
            } else {
                return Self.new(alloc); // use Cow.borrowed("") when implemented
            }
        };

        const REPLACEMENT: str = str{ .inner = "\xFF\xFD" };

        var res = try Self.withCapacity(alloc, v.len);
        res.pushStr(first_valid);
        res.pushStr(REPLACEMENT);

        while (iter.iterNext()) |chunk| {
            res.pushStr(chunk.valid);
            if (chunk.invalid.len != 0) {
                res.pushStr(REPLACEMENT);
            }
        }

        return res; // use Cow.owned(res) when implemented
    }

    // TODO: fromUtf16
    // TODO: fromUtf16Lossy
    // TODO: fromUtf16LE
    // TODO: fromUtf16LELossy
    // TODO: fromUtf16BE
    // TODO: fromUtf16BELossy

};

pub const Utf8Chunk = struct {
    valid: str,
    invalid: []const u8,
};

pub const Utf8Chunks = struct {
    source: []const u8,

    const Self = @This();

    fn fromBytes(bytes: []const u8) Self {
        return Self{ .source = bytes };
    }

    fn iterNext(self: *Self) ?Utf8Chunk {
        if (self.source.len == 0) {
            return null;
        }

        const TAG_CONT_U8: u8 = 128;
        var i: usize = 0;
        var valid_up_to = 0;

        while (i < self.source.len) {
            // SAFETY: `i < self.source.len()` per previous line.
            const byte = self.source[i];
            i += 1;

            if (byte < 128) {
                // This could be a `1 => ...` case in the match below, but for
                // the common case of all-ASCII inputs, we bypass loading the
                // sizeable UTF8_CHAR_WIDTH table into cache.
            } else {
                const w = utf8CharWidth(byte);

                switch (w) {
                    2 => {
                        if ((safe_get(self.source, i) & 192) != TAG_CONT_U8) break;
                        i += 1;
                    },
                    3 => {
                        const next_val = safe_get(self.source, i);
                        if (!((byte == 0xE0 and (next_val >= 0xA0 and next_val <= 0xBF)) or
                            ((byte >= 0xE1 and byte <= 0xEC) and (next_val >= 0x80 and next_val <= 0xBF)) or
                            (byte == 0xED and (next_val >= 0x80 and next_val <= 0x9F)) or
                            ((byte >= 0xEE and byte <= 0xEF) and (next_val >= 0x80 and next_val <= 0xBF))))
                        {
                            break;
                        }
                        i += 1;
                        if ((safe_get(self.source, i) & 192) != TAG_CONT_U8) break;
                        i += 1;
                    },
                    4 => {
                        const next_val = safe_get(self.source, i);
                        if (!((byte == 0xF0 and (next_val >= 0x90 and next_val <= 0xBF)) or
                            ((byte >= 0xF1 and byte <= 0xF3) and (next_val >= 0x80 and next_val <= 0xBF)) or
                            (byte == 0xF4 and (next_val >= 0x80 and next_val <= 0x8F))))
                        {
                            break;
                        }
                        i += 1;
                        if ((safe_get(self.source, i) & 192) != TAG_CONT_U8) break;
                        i += 1;
                        if ((safe_get(self.source, i) & 192) != TAG_CONT_U8) break;
                        i += 1;
                    },
                    else => break,
                }
            }
            valid_up_to = i;
        }

        // SAFETY: `i <= self.source.len()` because it is only ever incremented
        // via `i += 1` and in between every single one of those increments, `i`
        // is compared against `self.source.len()`. That happens either
        // literally by `i < self.source.len()` in the while-loop's condition,
        // or indirectly by `safe_get(self.source, i) & 192 != TAG_CONT_U8`. The
        // loop is terminated as soon as the latest `i += 1` has made `i` no
        // longer less than `self.source.len()`, which means it'll be at most
        // equal to `self.source.len()`.
        const inspected, const remaining = splitAtMut(self.source, i);
        self.source = remaining;

        // SAFETY: `valid_up_to <= i` because it is only ever assigned via
        // `valid_up_to = i` and `i` only increases.
        const valid, const invalid = splitAtMut(inspected, valid_up_to);

        return Utf8Chunk{
            .valid = str.fromUtf8Unchecked(valid),
            .invalid = invalid,
        };
    }

    fn splitAtMut(slice: []u8, mid: usize) struct { []u8, []u8 } {
        return .{
            slice[0..mid],
            slice[mid..],
        };
    }

    fn safe_get(xs: []u8, i: usize) u8 {
        if (i >= xs.len) {
            return 0;
        } else {
            return xs[i];
        }
    }
};