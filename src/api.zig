const std = @import("std");
const trace = @import("trace.zig");

var traced_from_raw = false;
var traced_load_file = false;

pub const c = @cImport({
    @cInclude("lua.h");
    @cInclude("lauxlib.h");
    @cInclude("lualib.h");
});

pub const LuaError = error{
    OutOfMemory,
    InvalidChunk,
    InvalidValue,
};

pub const State = struct {
    raw: *c.lua_State,

    pub fn init() LuaError!State {
        const raw = c.luaL_newstate() orelse return error.OutOfMemory;
        c.luaL_openlibs(raw);
        return .{ .raw = raw };
    }

    pub fn fromRaw(raw: *c.lua_State) State {
        trace.emitOnce(&traced_from_raw, "api.fromRaw raw={*}", .{raw});
        return .{ .raw = raw };
    }

    pub fn deinit(self: State) void {
        c.lua_close(self.raw);
    }

    pub fn loadFile(self: State, allocator: std.mem.Allocator, path: []const u8) !void {
        trace.emitOnce(&traced_load_file, "api.loadFile path={s}", .{path});
        const path_z = try allocator.dupeZ(u8, path);
        defer allocator.free(path_z);

        const filename: [*c]const u8 = @ptrCast(path_z.ptr);
        if (c.luaL_loadfilex(self.raw, filename, null) != c.LUA_OK) return error.InvalidChunk;
        if (c.lua_pcallk(self.raw, 0, c.LUA_MULTRET, 0, @as(c.lua_KContext, 0), null) != c.LUA_OK) {
            return error.InvalidValue;
        }
    }

    pub fn topIsTable(self: State) bool {
        return c.lua_istable(self.raw, -1);
    }

    pub fn pop(self: State, count: c_int) void {
        c.lua_pop(self.raw, count);
    }

    pub fn absIndex(self: State, idx: c_int) c_int {
        return c.lua_absindex(self.raw, idx);
    }

    pub fn rawLen(self: State, idx: c_int) usize {
        return @intCast(c.lua_rawlen(self.raw, idx));
    }

    pub fn rawGetIndex(self: State, idx: c_int, array_index: usize) void {
        _ = c.lua_rawgeti(self.raw, idx, @intCast(array_index));
    }

    pub fn getField(self: State, idx: c_int, name: []const u8) void {
        _ = c.lua_getfield(self.raw, idx, @ptrCast(name.ptr));
    }

    pub fn isTable(self: State, idx: c_int) bool {
        return c.lua_istable(self.raw, idx);
    }

    pub fn isInteger(self: State, idx: c_int) bool {
        return c.lua_isinteger(self.raw, idx) != 0;
    }

    pub fn isNumber(self: State, idx: c_int) bool {
        return c.lua_isnumber(self.raw, idx) != 0;
    }

    pub fn isBoolean(self: State, idx: c_int) bool {
        return c.lua_type(self.raw, idx) == c.LUA_TBOOLEAN;
    }

    pub fn readInteger(self: State, idx: c_int) i64 {
        return c.lua_tointegerx(self.raw, idx, null);
    }

    pub fn readNumber(self: State, idx: c_int) f64 {
        return c.lua_tonumberx(self.raw, idx, null);
    }

    pub fn readBoolean(self: State, idx: c_int) bool {
        return c.lua_toboolean(self.raw, idx) != 0;
    }

    pub fn readString(self: State, idx: c_int) ?[]const u8 {
        if (c.lua_type(self.raw, idx) != c.LUA_TSTRING) return null;
        var len: usize = 0;
        const ptr = c.lua_tolstring(self.raw, idx, &len) orelse return null;
        return ptr[0..len];
    }

    pub fn valueType(self: State, idx: c_int) c_int {
        return c.lua_type(self.raw, idx);
    }

    pub fn tableIter(self: State, idx: c_int) TableIter {
        return .{
            .state = self,
            .index = self.absIndex(idx),
            .started = false,
        };
    }
};

pub const TableIter = struct {
    state: State,
    index: c_int,
    started: bool,
    active: bool = false,

    pub fn next(self: *TableIter) bool {
        if (!self.started) {
            c.lua_pushnil(self.state.raw);
            self.started = true;
        } else if (self.active) {
            c.lua_pop(self.state.raw, 1);
        }
        self.active = c.lua_next(self.state.raw, self.index) != 0;
        return self.active;
    }

    pub fn keyString(self: TableIter) ?[]const u8 {
        return self.state.readString(-2);
    }

    pub fn valueString(self: TableIter) ?[]const u8 {
        return self.state.readString(-1);
    }

    pub fn finish(self: *TableIter) void {
        if (self.active) {
            c.lua_pop(self.state.raw, 2);
        }
        self.active = false;
        self.started = false;
    }
};

test "table iterator walks returned table" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "sample.lua", .data = "return { a = '1', b = '2' }\n" });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp.dir.realpath("sample.lua", &path_buf);

    var lua = try State.init();
    defer lua.deinit();
    try lua.loadFile(allocator, path);
    try std.testing.expect(lua.topIsTable());

    var it = lua.tableIter(-1);
    defer it.finish();

    var seen: usize = 0;
    while (it.next()) {
        if (it.keyString()) |key| {
            if (std.mem.eql(u8, key, "a") or std.mem.eql(u8, key, "b")) seen += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 2), seen);
}
