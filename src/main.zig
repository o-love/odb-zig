const std = @import("std");
const odb_zig = @import("odb_zig");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const Config = struct {
    allocator: Allocator,
    io: std.Io,
    pid: ?u32 = null,
    command: std.ArrayList([]const u8) = .{},


    fn deinit(config: *Config) !void {
        for (config.command.items) |c| {
            config.allocator.free(c);
        }

        config.command.deinit(config.allocator);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var config = try parse_args(allocator, io);
    defer config.deinit() catch {};

    try run_debugger(config);
}

fn parse_args(allocator: Allocator, io: std.Io) !Config {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var config = Config{
        .allocator = allocator,
        .io = io,
    };
    errdefer config.deinit() catch {};

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--pid")) {
            i += 1;
            config.pid = std.fmt.parseInt(u32, args[i], 10) catch {
                std.log.err("Unable to parse --pid as int: '{s}'", .{ args[i] });
                return error.InvalidArgs;
            };
        } else {
            const dupe = try allocator.dupeZ(u8, args[i]);
            try config.command.append(allocator, dupe);
        }
    }

    return config;
}

fn run_debugger(config: Config) !void {

    var input_buffer: [1024]u8 = undefined;
    var output_buffer: [1024]u8 = undefined;

    var input_f_reader = std.Io.File.stdin().reader(config.io, &input_buffer);
    var output_f_writer = std.Io.File.stdout().writer(config.io, &output_buffer);

    try odb_zig.RunDebugger(config.allocator, .{
        .command = config.command.items,
        .pid = config.pid orelse 0,
        .input = &input_f_reader.interface,
        .output = &output_f_writer.interface,
    });

    try output_f_writer.interface.flush();
}
