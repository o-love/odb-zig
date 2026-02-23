const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;
const panic = std.debug.panic;

const linux = @import("linux.zig");
const pid_t = linux.pid_t;
const LinuxError = linux.LinuxError;
pub const LaunchError = LinuxError;
const log = @import("log.zig");
const kill = linux.kill;
const SIGNAL = linux.SIGNAL;
const waitpid = linux.waitpid;

const Process = @This();

pid: pid_t,
state: State,

const State = enum {
    Running,
    Stopped,
};

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
        .state = .Stopped,
    };
}

pub fn launch(
    cmd: [*:null]const [*:0]const u8,
    envp: [*:null]const [*:0]const u8,
) LaunchError!@This() {
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
        .state = .Stopped,
    };
}

pub fn deinit(self: *@This()) !void {
    const dettach = linux.dettach;

    const pid = self.pid;
    assert(pid != 0);

    if (self.state == .Running) {
        try kill(pid, SIGNAL.STOP);
        _ = try waitpid(pid, 0);
    }

    try dettach(pid);

    try kill(pid, SIGNAL.KILL);
    _ = try waitpid(pid, 0);
}

test "attatch to process" {}
