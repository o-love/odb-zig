const std = @import("std");
const ProcessL = @import("process.zig").ProcessL;

const pid_t = std.posix.pid_t;
const File = std.Io.File;

pub const State = enum {
    Running,
    Sleeping,
    D_Sleep,
    Zombie,
    Trace_stop,
    X_Dead,
    K_Wakekill,
    Waking,
    Parked,
};

pub const StateParseError = error{
    UnkownState,
};

pub fn toState(stateChar: u8) StateParseError!State {
    return switch (stateChar) {
        'R' => State.Running,
        'S' => State.Sleeping,
        'D' => State.D_Sleep,
        'Z' => State.Zombie,
        'T' => State.Trace_stop,
        't' => State.Trace_stop,
        'X' => State.X_Dead,
        'x' => State.X_Dead,
        'K' => State.K_Wakekill,
        'W' => State.Waking,
        'P' => State.Parked,
    };
}

pub const Stat = struct {
    pid: pid_t,
    cmd: []const u8,
    state: State,
    ppid: pid_t,
    pgrp: pid_t,
    session: pid_t,
    // TODO: WIP
};

pub const StatL = struct {
    process: ProcessL,

    const Self = @This();

    fn getFilePath(self: *const Self) ![]const u8 {
        const intStr = try std.fmt.allocPrint(self.process.allocator, "{d}", .{self.process.pid});
        defer self.process.allocator.free(intStr);

        const pathFields = [_][]const u8{
            "/proc",
            intStr,
            "stat",
        };

        const statFilePath = try std.fs.path.join(
            self.process.allocator,
            pathFields[0..],
        );

        return statFilePath;
    }

    fn getFile(self: *const Self) File.OpenError!File {
        const statFilePath = self.getFilePath();
        defer self.process.allocator.free(statFilePath);

        const statFile = try std.Io.Dir.openFileAbsolute(self.process.io, statFilePath, .{});
        return statFile;
    }

    pub fn state() !State {}
};

test "Get stat file path" {
    const statL = StatL{
        .process = .{
            .allocator = std.testing.allocator,
            .io = std.testing.io,
            .pid = 1234,
        },
    };

    const path = try statL.getFilePath();
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings("/proc/1234/stat", path);
}
