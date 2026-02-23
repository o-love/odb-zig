const std = @import("std");

const linux = std.os.linux;
pub const pid_t = linux.pid_t;
const LinuxErrorValues = linux.E;
const errno = linux.errno;
const PTRACE_FLAGS = linux.PTRACE;
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

    toLinuxError(result) catch |err| switch (err) {
        .FAULT => std.debug.panic(efault_msg, .{}),
        .INVAL => std.debug.panic(einval_msg, .{}),
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

    try toLinuxError(result);

    return @intCast(result);
}

pub const WaitPidResult = struct {
    pid: pid_t,
    status: WaitPidStatus,
};

pub const WaitPidStatus = union(enum) {
    Exited: struct { exit_status: u8 },
    Signaled: struct { signal: u32 },
    Stopped: struct { signal: u32 },
    Continued,
};

pub const WaitPidError = error{
    InvalidStatus,
} || LinuxError;

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

pub fn waitpid(pid: pid_t, flags: u32) WaitPidError!WaitPidResult {
    var status: u32 = undefined;

    while (true) {
        const result = linux.waitpid(pid, &status, flags);

        switch (toLinuxError(result)) {
            .SUCCESS => return .{
                .pid = @intCast(result),
                .status = try mapWaitPid(status),
            },
            .INTR => continue,
            .INVAL => std.debug.panic(einval_msg, .{}),
            else => |err| return err,
        }
    }
}

pub fn execve(
    path: [*:0]const u8,
    argv: [*:null]const ?[*:0]const u8,
    envp: [*:null]const ?[*:0]const u8,
) LinuxError!void {
    const result = linux.execve(path, argv, envp);

    try toLinuxError(result);
}

pub const LinuxError = errorFromErrno(LinuxErrorValues);

fn toLinuxError(value: usize) LinuxError!void {
    switch (LinuxErrorValues.init(value)) {
        .SUCCESS => return,
        else => |e| {
            const e_value = @intFromEnum(e);

            inline for (@typeInfo(LinuxError).error_set.?) |err| {
                const err_val = @intFromEnum(@field(LinuxErrorValues, err.name));
                if (err_val == e_value) {
                    return @field(LinuxError, err.name);
                }
            }

            unreachable;
        },
    }
}

test toLinuxError {
    const testing = std.testing;
    const expectError = testing.expectError;

    try toLinuxError(0);

    const err_int: i64 = -1 * @as(i32, @intFromEnum(LinuxErrorValues.INTR));
    try expectError(
        LinuxError.INTR,
        toLinuxError(@bitCast(err_int)),
    );
}

fn errorFromErrno(comptime err_enum: type) type {
    const Error = std.builtin.Type.Error;

    const enum_fields = @typeInfo(err_enum).@"enum".fields;

    comptime var errs: []const Error = &.{};
    inline for (enum_fields) |field| {
        if (std.mem.eql(u8, field.name, "SUCCESS")) {
            continue;
        }

        const e = Error{
            .name = field.name,
        };

        errs = errs ++ .{e};
    }

    const e_set = @Type(.{ .error_set = errs[0..] });

    return e_set;
}
