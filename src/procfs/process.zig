const std = @import("std");

const pid_t = std.posix.pid_t;

pub const ProcessL = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    pid: pid_t,
};
