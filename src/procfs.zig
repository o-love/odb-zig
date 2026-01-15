const process_i = @import("procfs/process.zig");
const stat_i = @import("procfs/stat.zig");

pub const ProcessL = process_i.ProcessL;
pub const process = process_i.process;
pub const Stat = stat_i.Stat;
pub const StatL = stat_i.StatL;
pub const stat = stat_i.stat;
pub const State = stat_i.State;
