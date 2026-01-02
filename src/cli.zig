const std = @import("std");
const cmdUtils = @import("cmd.zig");
const Allocator = std.mem.Allocator;
const Process = @import("Process.zig");


pub const Cli = struct {
    const Self = @This();

    const HistoryList = std.ArrayList(cmdUtils.Cmd);
    history: HistoryList,

    gpa: Allocator,
    input: *std.Io.Reader,
    output: *std.Io.Writer,

    pub fn build(
        gpa: Allocator,
        input: *std.Io.Reader,
        output: *std.Io.Writer,
    ) !Cli {
        const history = try HistoryList.initCapacity(gpa, 16);

        return Cli{
            .history = history,

            .gpa = gpa,
            .input = input,
            .output = output,
        };
    }

    pub fn deinit(
        self: *Self,
    ) !void {
        self.history.deinit(self.gpa);
    }

    pub fn ask_cmd(
        self: *Cli,
    ) !cmdUtils.Cmd {
        var line_buffer: [1024]u8 = undefined;

        _ = try self.output.write("odb> ");
        try self.output.flush();

        const cmd_str = try read_line(&line_buffer, self.input);

        const cmd = try build_cmd(cmd_str);

        try self.history.append(self.gpa, cmd);

        return cmd;
    }

    pub fn handle_cmd(
        self: *const Cli,
        cmd: cmdUtils.Cmd,
        process: ?*Process,
    ) !i32 {
        return try cmd.run(cmdUtils.Cmd.RunParams{
            .process = process,

            .input = self.input,
            .output = self.output,
        });
    }
};

fn read_line(line_buffer: []u8, input: *std.Io.Reader) ![]u8 {
    var w: std.Io.Writer = .fixed(line_buffer);

    const line_length = try input.streamDelimiterLimit(&w, '\n', .limited(line_buffer.len));
    std.debug.assert(line_length <= line_buffer.len);
    // Consume /n
    _ = try input.takeByte();

    return line_buffer[0..line_length];
}


fn build_cmd(cmd: []const u8) !cmdUtils.Cmd {
    var cmdIter = std.mem.splitAny(u8, cmd, " ");

    const baseCmdStr = cmdIter.next().?;
    const baseCmd = cmdUtils.Cmd.parse(baseCmdStr, cmdIter.rest()).?;
    return baseCmd;
}



test "read line" {
    const test_input = "test input\ntest\n";
    var reader = std.Io.Reader.fixed(test_input);

    var line_buffer: [100]u8 = undefined;

    const line = try read_line(line_buffer[0..], &reader);
    try std.testing.expectEqualStrings("test input", line);

    const line2 = try read_line(line_buffer[0..], &reader);
    try std.testing.expectEqualStrings("test", line2);
}

test "handle_cmd ping pong" {
    const allocator = std.testing.allocator;

    var buf = [_]u8{0} ** 1024;
    var output_buffer: []u8 = buf[0..];
    var writer = std.Io.Writer.fixed(output_buffer);
    var reader = std.Io.Reader.failing;

    var cli = try Cli.build(allocator, &reader, &writer);
    defer cli.deinit() catch {};

    const cmd = try build_cmd("ping");

    const status = try cli.handle_cmd(cmd, null);

    try std.testing.expect(status >= 0);

    const result = output_buffer[0..writer.end];

    try std.testing.expectEqualStrings("pong -1\n", result);
}
