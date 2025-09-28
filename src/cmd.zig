const std = @import("std");
const OdbError = @import("errors.zig").OdbError;
const Process = @import("process.zig").Process;

pub const Cmd = union(enum) {
    ping: Ping,
    cont: Cont,
    breakpoint: Breakpoint,
    exit: Exit,

    const CmdInit = *const fn ([]const u8) Cmd;

    pub fn parse(str: []const u8, args: []const u8) ?Cmd {
        const hashmap = std.StaticStringMap(CmdInit).initComptime(.{
            .{ "ping", Ping.build },

            .{ "continue", Cont.build },
            .{ "cont", Cont.build },
            .{ "c", Cont.build },

            .{ "breakpoint", Breakpoint.build },
            .{ "break", Breakpoint.build },
            .{ "b", Breakpoint.build },

            .{ "exit", Exit.build },
        });

        const builder = hashmap.get(str);

        if (builder == null) {
            return null;
        }

        const result = builder.?(args);

        return result;
    }

    pub const RunParams = struct {
        process: ?*Process,

        input: *std.Io.Reader,
        output: *std.Io.Writer,
    };

    pub fn run(
        self: Cmd,
        params: RunParams,
    ) !i32 {
        switch (self) {
            inline else => |case| return case.run(params),
        }
    }

};

const Ping = struct {
    const Self = @This();

    pub fn build(
        _: [] const u8,
    ) Cmd {
        return Cmd{.ping = Self{}};
    }

    pub fn run(
        _: Self,
        params: Cmd.RunParams,
    ) !i32 {
        const pid = if (params.process) |p| p.pid else -1;

        try params.output.print("pong {d}\n", .{ pid });
        return 0;
    }
};

const Cont = struct {
    const Self = @This();

    pub fn build(
        _: [] const u8,
    ) Cmd {
        return Cmd{ .cont = Self{}};
    }

    pub fn run(
        _: Self,
        params: Cmd.RunParams,
    ) !i32 {
        errdefer params.output.print("failed to continue\n", .{}) catch {};

        const process: *Process = params.process orelse return OdbError.InvalidArg;

        try process.resume_p();

        try params.output.print("continuing {d}\n", .{process.pid});

        _ = process.wait_on_signal();

        return 0;
    }
};

const Breakpoint = struct {
    const Self = @This();

    pub fn build(
        _: [] const u8,
    ) Cmd {
        return Cmd{ .breakpoint = Self{}};
    }

    pub fn run(
        _: Self,
        params: Cmd.RunParams,
    ) !i32 {
        try params.output.print("break\n", .{});
        return 0;
    }
};

const Exit = struct {
    const Self = @This();

    pub fn build(
        _: [] const u8,
    ) Cmd {
        return Cmd{ .exit = Self{}};
    }


    pub fn run(
        _: Self,
        params: Cmd.RunParams,
    ) !i32 {
        try params.output.print("goodbye!\n", .{});
        return OdbError.ExitRequest;
    }
};