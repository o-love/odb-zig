const std = @import("std");

const File = std.Io.File;

reader_file: ?File,
writer_file: ?File,

const Pipe = @This();

pub const CreateError = error{
    PipeCreateError,
    InvalidFdError,
};

pub const ConversionError = error{
    FdAlreadyClosed,
};

pub fn create() CreateError!@This() {
    const pipe = std.os.linux.pipe;
    const min = std.mem.min;

    var pipe_fds = std.mem.zeroes([2]i32);

    const pipe_ret = pipe(&pipe_fds);
    if (pipe_ret != 0) {
        return CreateError.PipeCreateError;
    }

    if (min(i32, &pipe_fds) < 0) {
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

fn fileFromFd(fd: i32) File {
    return .{ .handle = fd };
}

pub fn toReader(pipe: *@This(), io: std.Io) ConversionError!*std.Io.File {
    if (pipe.writer_file) |w| {
        w.close(io);
        pipe.writer_file = null;
    }

    if (pipe.reader_file) |_| {
        return &pipe.reader_file.?;
    }

    return ConversionError.FdAlreadyClosed;
}

pub fn toWriter(pipe: *@This(), io: std.Io) ConversionError!*std.Io.File {
    if (pipe.reader_file) |r| {
        r.close(io);
        pipe.reader_file = null;
    }

    if (pipe.writer_file) |_| {
        return &pipe.writer_file.?;
    }

    return ConversionError.FdAlreadyClosed;
}

test "Fork pipe IPC" {
    const fork = std.posix.fork;
    const io = std.testing.io;

    var pipe = try Pipe.create();
    defer pipe.deinit(io);

    var pipe_buf: [1024]u8 = undefined;

    const pid = try fork();

    if (pid == 0) {
        const writer_file = try pipe.toWriter(io);
        const writer_obj = writer_file.writer(io, &pipe_buf);
        var writer = writer_obj.interface;

        _ = try writer.write("hello\n");
        try writer.flush();

        writer_file.close(io);

        std.os.linux.exit(0);
    }

    const reader_file = try pipe.toReader(io);
    defer reader_file.close(io);

    const reader_obj = reader_file.reader(io, &pipe_buf);
    var reader = reader_obj.interface;

    const read_result = try reader.takeDelimiter('\n');

    try std.testing.expect(read_result != null);

    try std.testing.expectEqualStrings("hello", read_result.?);
}
