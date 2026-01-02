//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const Allocator = std.mem.Allocator;
const Process = @import("Process.zig");
const Cli = @import("cli.zig").Cli;
const OdbError = @import("errors.zig").OdbError;

pub const Options = struct {
    pid: u32 = 0,
    command: []const []const u8 = undefined,
    input: *std.Io.Reader,
    output: *std.Io.Writer,
};

pub fn RunDebugger(gpa: Allocator, opts: Options) !void {
    std.log.debug("starting run.", .{});

    var process: Process = undefined;

    if (opts.pid == 0) {
        process = try Process.launch(gpa, opts.command);
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
                OdbError.ExitRequest => {
                    break;
                },
                else => {
                    return err;
                },
            }
        };
    }
}

test "odb-zig" {
    _ = @import("cli.zig");
    _ = @import("cmd.zig");
    _ = @import("Process.zig");
}
