const std = @import("std");
const odg_zig = @import("root.zig");

const Allocator = std.mem.Allocator;
const system = std.posix;
const PTRACE = std.os.linux.PTRACE;
const ptrace = system.ptrace;
const panic = std.debug.panic;
const OdbError = odg_zig.OdbError;
const Pipe = odg_zig.Pipe;

const Process = @This();

const State = enum {
    stopped,
    running,
    exited,
    terminated,
};

const Private = struct {
    terminate_on_end: bool = false,
    process_state: State,
};

pid: i32,
private: Private,

pub fn launch(io: std.Io, gpa: Allocator, cmd: []const []const u8) !@This() {
    const fork = system.fork;
    const execv = std.process.execv;

    var pipe = try Pipe.create();
    defer pipe.deinit(io);

    var pipe_buf: [1024]u8 = undefined;

    const pid = try fork();

    if (pid == 0) {
        var write_file = try pipe.toWriter(io);
        defer write_file.close(io);

        var pipe_writer = write_file.writer(io, &pipe_buf);
        const writer = pipe_writer.interface;
        _ = writer;

        try traceme(0);

        const err = execv(gpa, cmd);

        panic("execv faild with {}\n", .{err});
    }

    if (pid <= 0) {
        std.log.err("launch got invalid pid: {d}\n", .{pid});
        return OdbError.InvalidArg;
    }

    var read_file = try pipe.toReader(io);
    defer read_file.close(io);

    var pipe_reader = read_file.reader(io, &pipe_buf);
    const reader = pipe_reader.interface;

    _ = reader;

    std.log.debug("spawned process with pid: {d}\n", .{pid});

    const self = @This(){
        .pid = pid,
        .private = .{
            .process_state = State.stopped,
        },
    };

    _ = self.wait_on_signal();

    return self;
}

pub fn attach(pid: i32) !@This() {
    try ptrace(PTRACE.ATTACH, pid, 0, 0);

    return @This(){
        .pid = pid,
        .private = .{
            .process_state = State.stopped,
        },
    };
}

pub fn cleanup(self: *@This()) !void {
    const SIGKILL = std.posix.SIG.KILL;

    if (self.private.terminate_on_end) {
        self.kill(SIGKILL);
        self.wait_until_exit();

        self.private.process_state = State.terminated;
        self.pid = -1;
    }
}

pub fn resume_p(self: *const @This()) !void {
    try ptrace(PTRACE.CONT, self.pid, 0, 0);
}

fn traceme(pid: i32) !void {
    try ptrace(PTRACE.TRACEME, pid, 0, 0);
}

pub fn wait_on_signal(self: *const @This()) u32 {
    const waitpid = system.waitpid;

    const wait_result = waitpid(self.pid, 0);
    std.log.debug("waitpid for {d} returned {d}\n", .{ wait_result.pid, wait_result.status });

    return wait_result.status;
}

pub fn wait_until_exit(self: *const @This()) !u8 {
    const has_exited = std.os.linux.W.IFEXITED;
    const exit_signal = std.os.linux.W.EXITSTATUS;

    while (true) {
        const signal = self.wait_on_signal();

        if (has_exited(signal)) {
            return exit_signal(signal);
        }

        try self.resume_p();
    }
}

pub fn wait_until_stop(self: *const @This()) !u32 {
    const is_stopped = std.os.linux.W.IFSTOPPED;
    const stop_signal = std.os.linux.W.STOPSIG;

    while (true) {
        const signal = self.wait_on_signal();

        if (is_stopped(signal)) {
            return stop_signal(signal);
        }

        try self.resume_p();
    }
}

pub fn kill(self: *const @This(), signal: std.posix.SIG) !void {
    return std.posix.kill(self.pid, signal);
}

test "wait_on_signal waits until process finishes" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    const cmd = [_][]const u8{ "/usr/bin/env", "bash", "-c", "sleep 1" };

    const p = try Process.launch(io, allocator, &cmd);
    try p.resume_p();

    _ = try p.wait_until_exit();

    const ProcessNotFound = std.posix.KillError.ProcessNotFound;
    const SIGKILL = std.posix.SIG.KILL;
    const kill_res = p.kill(SIGKILL);

    try std.testing.expectError(ProcessNotFound, kill_res);
}

test "launch non existent process returns error" {
    // TODO: Work on piped error passing from forked process.
}

test "continue terminated process" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    const cmd = [_][]const u8{ "/usr/bin/env", "bash", "-c", "sleep 1" };

    const p = try Process.launch(io, allocator, &cmd);
    try p.resume_p();

    _ = try p.wait_until_exit();

    const not_error = p.resume_p();

    if (not_error) {
        @panic("Expected an error");
    } else |_| {}
}
