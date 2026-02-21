const std = @import("std");

const linux = std.os.linux;
pub const pid_t = linux.pid_t;
pub const LinuxError = linux.E;
const errno = linux.errno;
const PTRACE_FLAGS = linux.PTRACE;
const panic = std.debug.panic;
const log = @import("log.zig");

const einval_msg = "EINVAL: Invalid Argument";
const efault_msg = "EFAULT: Bad Address";

fn ptrace(
    req: u32,
    pid: pid_t,
    addr: usize,
    data: usize,
    addr2: usize,
) LinuxError!void {
    const result = linux.ptrace(req, pid, addr, data, addr2);

    return switch (LinuxError.init(result)) {
        .SUCCESS => void,
        .FAULT => panic(efault_msg, .{}),
        .INVAL => panic(einval_msg, .{}),
        else => |e| e,
    };
}

pub fn attach(pid: pid_t) LinuxError!void {
    return ptrace(
        PTRACE_FLAGS.ATTACH,
        pid,
        0,
        0,
        0,
    );
}

pub fn fork() LinuxError!pid_t {
    const result = linux.fork();

    switch (LinuxError.init(result)) {
        .SUCCESS => return @intCast(result),
        else => |err| return err,
    }
}

pub const WaitPidResult = struct {
    pid: pid_t,
    status: u32,
};

pub const WaitPidStatus = union(enum) {
    Exited: struct { exit_status: u8 },
    Signaled: struct { signal: u32 },
    Stopped: struct { signal: u32 },
    Continued,
};

pub const WaitPidError = error{
    InvalidStatus,
};

fn mapWaitPid(status: u32) WaitPidError!WaitPidStatus {
    const W = linux.W;

    if (W.IFEXITED(status)) {
        return WaitPidStatus{ .Exited = .{
            .exit_status = W.EXITSTATUS(status),
        } };
    } else if (W.IFSIGNALED(status)) {
        return WaitPidStatus{ .Signaled = .{
            .signal = W.TERMSIG(status),
        } };
    } else if (W.IFSTOPPED(status)) {
        return WaitPidStatus{ .Stopped = .{
            .signal = W.STOPSIG(status),
        } };
    }

    log.err("Unable to parse waitpid status {}", .{status});
    return WaitPidError.InvalidStatus;
}

test mapWaitPid {
    const testing = std.testing;
    const expectEqual = testing.expectEqual;

    const res = try mapWaitPid(0);
    try expectEqual(WaitPidStatus{ .Exited = .{ .exit_status = 0 } }, res);
}

pub fn waitpid(pid: pid_t, flags: u32) !WaitPidResult {
    var status: u32 = undefined;

    while (true) {
        const result = linux.waitpid(pid, &status, flags);

        switch (LinuxError.init(result)) {
            .SUCCESS => return .{
                .pid = @intCast(result),
                .status = @bitCast(status),
            },
            .INTR => continue,
            .INVAL => panic(einval_msg, .{}),
            else => |err| return err,
        }
    }
}

pub fn execve(
    path: [*:0]const u8,
    argv: [*:null]const ?[*:0]const u8,
    envp: [*:null]const ?[*:0]const u8,
) !void {
    const result = linux.execve(path, argv, envp);

    return LinuxError.init(result);
}
