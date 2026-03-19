const std = @import("std");

pub fn toCStringArray(
    allocator: std.mem.Allocator,
    slice: []const [:0]const u8,
) ![*:null]const ?[*:0]const u8 {
    // allocSentinel gives us [:null]?[*:0]const u8, which coerces to [*:null]
    const result = try allocator.allocSentinel(?[*:0]const u8, slice.len, null);

    for (slice, result) |src, *dst| {
        dst.* = src.ptr;
    }

    return result.ptr;
}
