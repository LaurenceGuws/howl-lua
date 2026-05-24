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
            const owned = try self.allocator.dupe(u8, raw);
            self.allocator.free(target.*);
            target.* = owned;
        }
    }

    pub fn optionalStringOwned(self: Reader, field: []const u8, target: *?[]u8) !void {
        self.state.pushField(self.index, field);
        defer self.state.pop(1);
        if (self.state.readString(-1)) |raw| {
            const owned = try self.allocator.dupe(u8, raw);
            if (target.*) |current| self.allocator.free(current);
            target.* = owned;
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
        const value = self.state.readInteger(-1) orelse return;
        target.* = std.math.cast(T, value) orelse return;
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

test "reader numeric field contracts are strict" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "numbers.lua", .data = "return { int_value = 7, float_value = 2.5, int_string = '7', float_string = '2.5' }\n" });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp.dir.realpath("numbers.lua", &path_buf);

    var state = try api.State.init();
    defer state.deinit();
    try state.loadFile(allocator, path);

    const reader = Reader.init(state, allocator, -1);

    try std.testing.expectEqual(@as(i64, 7), reader.intField("int_value") orelse return error.TestUnexpectedResult);
    try std.testing.expect(reader.intField("float_value") == null);
    try std.testing.expect(reader.intField("int_string") == null);

    try std.testing.expectEqual(@as(f64, 7), reader.numberField("int_value") orelse return error.TestUnexpectedResult);
    try std.testing.expectEqual(@as(f64, 2.5), reader.numberField("float_value") orelse return error.TestUnexpectedResult);
    try std.testing.expect(reader.numberField("float_string") == null);
}

test "intInto ignores out-of-range values without trapping" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "range.lua", .data = "return { huge = 500, exact = 12 }\n" });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp.dir.realpath("range.lua", &path_buf);

    var state = try api.State.init();
    defer state.deinit();
    try state.loadFile(allocator, path);

    const reader = Reader.init(state, allocator, -1);
    var small: u8 = 9;
    reader.intInto(u8, "huge", &small);
    try std.testing.expectEqual(@as(u8, 9), small);

    reader.intInto(u8, "exact", &small);
    try std.testing.expectEqual(@as(u8, 12), small);
}

test "stringOwned leaves target unchanged on missing or wrong-type field" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "strings.lua", .data = "return { present = 'ok', wrong = true }\n" });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp.dir.realpath("strings.lua", &path_buf);

    var state = try api.State.init();
    defer state.deinit();
    try state.loadFile(allocator, path);

    const reader = Reader.init(state, allocator, -1);
    var value = try allocator.dupe(u8, "keep");
    defer allocator.free(value);

    try reader.stringOwned("missing", &value);
    try std.testing.expectEqualStrings("keep", value);

    try reader.stringOwned("wrong", &value);
    try std.testing.expectEqualStrings("keep", value);

    try reader.stringOwned("present", &value);
    try std.testing.expectEqualStrings("ok", value);
}

test "optionalStringOwned leaves target unchanged on nil missing or wrong-type field" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "optional.lua", .data = "return { present = 'ok', cleared = nil, wrong = false }\n" });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp.dir.realpath("optional.lua", &path_buf);

    var state = try api.State.init();
    defer state.deinit();
    try state.loadFile(allocator, path);

    const reader = Reader.init(state, allocator, -1);
    var value: ?[]u8 = try allocator.dupe(u8, "keep");
    defer if (value) |owned| allocator.free(owned);

    try reader.optionalStringOwned("missing", &value);
    try std.testing.expectEqualStrings("keep", value orelse return error.TestUnexpectedResult);

    try reader.optionalStringOwned("cleared", &value);
    try std.testing.expectEqualStrings("keep", value orelse return error.TestUnexpectedResult);

    try reader.optionalStringOwned("wrong", &value);
    try std.testing.expectEqualStrings("keep", value orelse return error.TestUnexpectedResult);

    try reader.optionalStringOwned("present", &value);
    try std.testing.expectEqualStrings("ok", value orelse return error.TestUnexpectedResult);
}

test "owned string helpers are stack neutral" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "owned-depth.lua", .data = "return { present = 'ok', wrong = 1 }\n" });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp.dir.realpath("owned-depth.lua", &path_buf);

    var state = try api.State.init();
    defer state.deinit();
    try state.loadFile(allocator, path);

    const reader = Reader.init(state, allocator, -1);
    const before = api.c.lua_gettop(state.raw);

    var value = try allocator.dupe(u8, "x");
    defer allocator.free(value);
    try reader.stringOwned("present", &value);
    try std.testing.expectEqual(before, api.c.lua_gettop(state.raw));

    try reader.stringOwned("wrong", &value);
    try std.testing.expectEqual(before, api.c.lua_gettop(state.raw));

    var optional: ?[]u8 = try allocator.dupe(u8, "y");
    defer if (optional) |owned| allocator.free(owned);
    try reader.optionalStringOwned("present", &optional);
    try std.testing.expectEqual(before, api.c.lua_gettop(state.raw));

    try reader.optionalStringOwned("missing", &optional);
    try std.testing.expectEqual(before, api.c.lua_gettop(state.raw));
}

test "owned string helpers preserve prior value on allocation failure" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "oom.lua", .data = "return { present = 'ok' }\n" });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp.dir.realpath("oom.lua", &path_buf);

    var state = try api.State.init();
    defer state.deinit();
    try state.loadFile(allocator, path);

    const reader = Reader.init(state, allocator, -1);

    var failing = std.testing.FailingAllocator.init(allocator, .{ .fail_index = 0 });
    const failing_reader = Reader.init(state, failing.allocator(), -1);

    var value = try allocator.dupe(u8, "keep");
    defer allocator.free(value);
    try std.testing.expectError(error.OutOfMemory, failing_reader.stringOwned("present", &value));
    try std.testing.expectEqualStrings("keep", value);

    var optional: ?[]u8 = try allocator.dupe(u8, "keep2");
    defer if (optional) |owned| allocator.free(owned);
    try std.testing.expectError(error.OutOfMemory, failing_reader.optionalStringOwned("present", &optional));
    try std.testing.expectEqualStrings("keep2", optional orelse return error.TestUnexpectedResult);

    _ = reader;
}
