const std = @import("std");

pub const OnceFlag = std.atomic.Value(bool);

pub fn enabled() bool {
    const raw = std.c.getenv("HOWL_LUA_TRACE") orelse return false;
    const value = std.mem.sliceTo(raw, 0);
    return value.len == 0 or !std.mem.eql(u8, value, "0");
}

pub fn emitOnce(flag: *OnceFlag, comptime fmt: []const u8, args: anytype) void {
    if (!enabled()) return;
    if (flag.cmpxchgStrong(false, true, .acq_rel, .acquire) != null) return;
    std.debug.print("howl_lua: " ++ fmt ++ "\n", args);
}
