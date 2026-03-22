//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const Allocator = std.mem.Allocator;
const Process = @import("Process.zig");
const Cli = @import("cli.zig").Cli;
const cUtils = @import("cUtils.zig");

pub const Options = struct {
    pid: u32 = 0,
    command: []const [:0]const u8 = undefined,
    envp: []const [:0]const u8 = undefined,
    input: *std.Io.Reader,
    output: *std.Io.Writer,

    fn launchProcess(self: *const Options, gpa: Allocator) !Process {
        const toC = cUtils.toCStringArray;
        const cmd = try toC(gpa, self.command);
        defer gpa.free(cmd);

        const envp = try toC(gpa, self.envp);
        defer gpa.free(envp);

        return Process.launch(cmd.ptr, envp.ptr);
    }
};

pub fn RunDebugger(gpa: Allocator, opts: Options) !void {
    std.log.debug("starting run.", .{});

    var process: Process = undefined;

    if (opts.pid == 0) {
        if (opts.command.len == 0) {
            std.log.err("No pid to attatch to provided and no process provided", .{});
            return;
        }

        process = try opts.launchProcess(gpa);
    } else {
        if (std.math.cast(i32, opts.pid)) |pidI| {
            process = try Process.attach(pidI);
        } else {
            std.log.err("Unable to cast pid to i32", .{});
            return;
        }
    }

    var cli = try Cli.build(gpa, opts.input, opts.output);
    defer cli.deinit() catch {};

    var status: i32 = 0;
    while (status >= 0) {
        const cmd = cli.ask_cmd() catch |err| {
            switch (err) {
                else => {
                    return err;
                },
            }
        };

        status = cli.handle_cmd(cmd, &process) catch |err| {
            switch (err) {
                error.ExitRequest => {
                    break;
                },
                else => {
                    return err;
                },
            }
        };
    }
}

test {
    _ = @import("log.zig");
    _ = @import("Process.zig");
    _ = @import("cli.zig");
    _ = @import("cmd.zig");
    _ = @import("cUtils.zig");
}
