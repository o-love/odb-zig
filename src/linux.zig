const std = @import("std");

const linux = std.os.linux;
pub const pid_t = linux.pid_t;
pub const LinuxError = linux.E;
const errno = linux.errno;
const PTRACE_FLAGS = linux.PTRACE;

fn ptrace(
    req: u32,
    pid: pid_t,
    addr: usize,
    data: usize,
    addr2: usize,
) LinuxError!void {
    const l_ptrace = linux.ptrace;

    const result = l_ptrace(req, pid, addr, data, addr2);


    return switch (LinuxError.init(result)) {
        .SUCCESS => void,
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