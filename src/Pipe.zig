const std = @import("std");

const File = std.Io.File;

reader_file: ?File,
writer_file: ?File,

const Pipe = @This();

pub const CreateError = error{
    InvalidFdError,
} || std.Io.Threaded.PipeError;

pub const ConversionError = error{
    FdAlreadyClosed,
};

pub const PipeCreateOpts = struct {
    CLOEXEC: bool = false,
    DIRECT: bool = false,
    NONBLOCK: bool = false,
    // NOTIFICATION_PIPE: bool = false,
};

pub fn create(opts: PipeCreateOpts) CreateError!@This() {
    const pipe2 = std.Io.Threaded.pipe2;
    const min = std.mem.min;

    var pipe_fds = try pipe2(
        .{
            .CLOEXEC = opts.CLOEXEC,
            .DIRECT = opts.DIRECT,
            .NONBLOCK = opts.NONBLOCK,
            // .NOTIFICATION_PIPE = opts.NOTIFICATION_PIPE,
        },
    );

    if (min(File.Handle, &pipe_fds) < 0) {
        return CreateError.InvalidFdError;
    }

    return .{
        .reader_file = fileFromFd(pipe_fds[0]),
        .writer_file = fileFromFd(pipe_fds[1]),
    };
}

pub fn deinit(pipe: *@This(), io: std.Io) void {
    if (pipe.writer_file) |file| {
        file.close(io);
    }

    if (pipe.reader_file) |file| {
        file.close(io);
    }

    pipe.* = undefined;
}

fn fileFromFd(fd: File.Handle) File {
    return .{ .handle = fd };
}

pub fn toReader(pipe: *@This(), io: std.Io, buffer: []u8) ConversionError!File.Reader {
    if (pipe.writer_file) |w| {
        w.close(io);
        pipe.writer_file = null;
    }

    if (pipe.reader_file) |_| {
        var file = &pipe.reader_file.?;
        return file.reader(io, buffer);
    }

    return ConversionError.FdAlreadyClosed;
}

pub fn toWriter(pipe: *@This(), io: std.Io, buffer: []u8) ConversionError!File.Writer {
    if (pipe.reader_file) |r| {
        r.close(io);
        pipe.reader_file = null;
    }

    if (pipe.writer_file) |_| {
        var file = &pipe.writer_file.?;
        return file.writer(io, buffer);
    }

    return ConversionError.FdAlreadyClosed;
}

test "Fork pipe IPC" {
    const posix = std.posix;
    const linux = std.os.linux;
    const io = std.testing.io;

    var pipe = try Pipe.create(.{});
    defer pipe.deinit(io);

    var pipe_buf: [1024]u8 = undefined;

    const pid: posix.pid_t = fork: {
        const rc = linux.fork();
        switch (posix.errno(rc)) {
            .SUCCESS => break :fork @intCast(rc),
            .AGAIN => return error.SystemResources,
            .NOMEM => return error.SystemResources,
            .NOSYS => return error.OperationUnsupported,
            else => |err| return posix.unexpectedErrno(err),
        }
    };

    if (pid == 0) {
        var writer = try pipe.toWriter(io, &pipe_buf);

        _ = try writer.interface.write("hello\n");
        try writer.interface.flush();

        pipe.deinit(io);
        std.process.exit(0);
    }

    var reader = try pipe.toReader(io, &pipe_buf);

    const read_result = try reader.interface.takeDelimiter('\n');

    try std.testing.expect(read_result != null);

    try std.testing.expectEqualStrings("hello", read_result.?);
}
