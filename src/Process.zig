const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;

const linux = @import("linux.zig");
const pid_t = linux.pid_t;
const log = @import("log.zig");
const LinuxError = linux.LinuxError;
const panic = std.debug.panic;

const Process = @This();

pid: pid_t,

pub const AttachError = error{
    InvalidArgument,
    PermissionDenied,
    ProcessNotFound,
} || LinuxError;

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
        },
    };

    return @This(){
        .pid = pid,
    };
}

pub const LaunchError = LinuxError;

pub fn launch(
    cmd: [*:null]const [*:0]const u8,
    envp: [*:null]const [*:0]const u8,
) LaunchError!@This() {
    const waitpid = linux.waitpid;
    const fork = linux.fork;
    const execve = linux.execve;

    const pid = try fork();
    assert(pid >= 0);

    if (pid == 0) {
        // Forked process

        // TODO: Add traceme

        execve(cmd[0], cmd, envp);

        // TODO: Return error with pipe

        panic("Execve Failed", .{});
    }

    const wait_result = try waitpid(pid, 0);
    assert(pid == wait_result.pid);

    return .{
        .pid = pid,
    };
}

test "attatch to process" {}
