const std = @import("std");
const api = @import("api.zig");
const trace = @import("trace.zig");

var traced_bool_field = false;
var traced_number_field = false;

pub const Reader = struct {
    state: api.State,
    allocator: std.mem.Allocator,
    index: c_int,

    pub fn init(state: api.State, allocator: std.mem.Allocator, index: c_int) Reader {
        return .{
            .state = state,
            .allocator = allocator,
            .index = state.absIndex(index),
        };
    }

    pub fn stringOwned(self: Reader, field: []const u8, target: *[]u8) !void {
        self.state.pushField(self.index, field);
        defer self.state.pop(1);
        if (self.state.readString(-1)) |raw| {
            self.allocator.free(target.*);
            target.* = try self.allocator.dupe(u8, raw);
        }
    }

    pub fn optionalStringOwned(self: Reader, field: []const u8, target: *?[]u8) !void {
        self.state.pushField(self.index, field);
        defer self.state.pop(1);
        if (self.state.readString(-1)) |raw| {
            if (target.*) |current| self.allocator.free(current);
            target.* = try self.allocator.dupe(u8, raw);
        }
    }

    pub fn boolField(self: Reader, field: []const u8) ?bool {
        self.state.pushField(self.index, field);
        defer self.state.pop(1);
        trace.emitOnce(&traced_bool_field, "reader.boolField field={s}", .{field});
        if (!self.state.isBoolean(-1)) return null;
        return self.state.readBoolean(-1);
    }

    pub fn intInto(self: Reader, comptime T: type, field: []const u8, target: *T) void {
        self.state.pushField(self.index, field);
        defer self.state.pop(1);
        if (self.state.isInteger(-1)) target.* = @intCast(self.state.readInteger(-1));
    }

    pub fn intField(self: Reader, field: []const u8) ?i64 {
        self.state.pushField(self.index, field);
        defer self.state.pop(1);
        if (!self.state.isInteger(-1)) return null;
        return self.state.readInteger(-1);
    }

    pub fn boolInto(self: Reader, field: []const u8, target: *bool) void {
        self.state.pushField(self.index, field);
        defer self.state.pop(1);
        if (self.state.valueType(-1) == api.c.LUA_TBOOLEAN) target.* = self.state.readBoolean(-1);
    }

    pub fn numberField(self: Reader, field: []const u8) ?f64 {
        self.state.pushField(self.index, field);
        defer self.state.pop(1);
        trace.emitOnce(&traced_number_field, "reader.numberField field={s}", .{field});
        if (!self.state.isNumber(-1)) return null;
        return self.state.readNumber(-1);
    }

    pub fn arrayLen(self: Reader) usize {
        return self.state.rawLen(self.index);
    }

    pub fn scalarStringOwned(self: Reader, idx: c_int) ![]u8 {
        return switch (self.state.valueType(idx)) {
            api.c.LUA_TSTRING => self.allocator.dupe(u8, self.state.readString(idx) orelse ""),
            api.c.LUA_TBOOLEAN => self.allocator.dupe(u8, if (self.state.readBoolean(idx)) "true" else "false"),
            api.c.LUA_TNUMBER => std.fmt.allocPrint(self.allocator, "{d}", .{self.state.readInteger(idx)}),
            else => self.allocator.dupe(u8, ""),
        };
    }
};

test "reader reads typed table fields" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "reader.lua", .data = "return { name = 'ok', count = 7, flag = true }\n" });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp.dir.realpath("reader.lua", &path_buf);

    var state = try api.State.init();
    defer state.deinit();
    try state.loadFile(allocator, path);

    const table_reader = Reader.init(state, allocator, -1);
    var name = try allocator.dupe(u8, "x");
    defer allocator.free(name);
    var count: u16 = 0;
    var flag = false;

    try table_reader.stringOwned("name", &name);
    table_reader.intInto(u16, "count", &count);
    table_reader.boolInto("flag", &flag);

    try std.testing.expectEqualStrings("ok", name);
    try std.testing.expectEqual(@as(u16, 7), count);
    try std.testing.expect(flag);
}

test "reader field helpers preserve stack depth" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "depth.lua", .data = "return { name = 'ok', count = 7, flag = true, ratio = 2.5 }\n" });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp.dir.realpath("depth.lua", &path_buf);

    var state = try api.State.init();
    defer state.deinit();
    try state.loadFile(allocator, path);

    const table_reader = Reader.init(state, allocator, -1);
    const before = api.c.lua_gettop(state.raw);

    _ = table_reader.boolField("flag");
    try std.testing.expectEqual(before, api.c.lua_gettop(state.raw));

    _ = table_reader.intField("count");
    try std.testing.expectEqual(before, api.c.lua_gettop(state.raw));

    _ = table_reader.numberField("ratio");
    try std.testing.expectEqual(before, api.c.lua_gettop(state.raw));

    var name = try allocator.dupe(u8, "x");
    defer allocator.free(name);
    try table_reader.stringOwned("name", &name);
    try std.testing.expectEqual(before, api.c.lua_gettop(state.raw));
}
