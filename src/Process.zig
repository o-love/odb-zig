const Process = @This();

const std = @import("std");
const linux = @import("linux.zig");
const log = @import("log.zig");
const pid_t = linux.pid_t;

pid: pid_t,

pub const AttachError = error {
    InvalidArgument,
    PermissionDenied,
    ProcessNotFound,
} || linux.LinuxError;

pub fn attach(pid: pid_t) AttachError!@This() {
    if (pid <= 0) {
        log.err("Called attach with invalid pid: {}", .{pid});
        return AttachError.InvalidArgument;
    }

    linux.attach(pid) catch |err| switch (err) {
        .PERM => {
            log.err("Insufficient permission to attach");
            return AttachError.PermissionDenied;
        },
        .SRCH => {
            log.err("Process to attach to not found");
            return AttachError.ProcessNotFound;
        },
        else => {
            return err;
        }
    };

    return @This(){
        .pid = pid,
    };
}

pub fn launch(cmd: []const u8) !@This() {}

const testing = std.testing;
test "attatch to process" {}
