const std = @import("std");
const log = std.log.scoped(.odb);

pub const info = log.info;
pub const debug = log.debug;
pub const err = log.err;
pub const warn = log.warn;
