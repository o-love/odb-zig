const Process = @This();

const std = @import("std");
const linux = @import("linux.zig");
const log = @import("log.zig");
const pid_t = linux.pid_t;

pid: pid_t,

pub const AttatchError = error {
    PermissionDenied,
    ProcessNotFound,
} || linux.LinuxError;

pub fn attatch(pid: pid_t) !@This() {
    if (pid <= 0) {
        log.err("Called attach with invalid pid: {}", .{pid});
        return error.InvalidArgument;
    }

    linux.attach(pid) catch |err| switch (err) {
        .PERM => {
            log.err("Insufficient permission to attach");
            return .PermissionDenied;
        },
        .SRCH => {
            log.err("Process to attach to not found");
            return .ProcessNotFound;
        },
        else => {
            log.debug("Unhandled error for attach ptrace call");
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
