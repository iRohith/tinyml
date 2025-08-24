const std = @import("std");

pub inline fn cast(comptime T: type, val: anytype) T {
    if (T == @TypeOf(val)) return val;
    const I0 = @typeInfo(T);
    const I1 = @typeInfo(@TypeOf(val));
    return switch (I0) {
        .float, .comptime_float => switch (I1) {
            .int, .comptime_int => @as(T, @floatFromInt(val)),
            .float, .comptime_float => @as(T, @floatCast(val)),
            else => @compileError("Invalid type."),
        },
        .int, .comptime_int => switch (I1) {
            .int, .comptime_int => @as(T, @intCast(val)),
            .float, .comptime_float => @as(T, @intFromFloat(val)),
            else => @compileError("Invalid type."),
        },
        .vector => |v| switch (@typeInfo(v.child)) {
            .float, .comptime_float => switch (I1) {
                .int, .comptime_int => @as(T, @splat(@floatFromInt(val))),
                .float, .comptime_float => @as(T, @splat(@floatCast(val))),
                .vector => |v1| switch (@typeInfo(v1.child)) {
                    .int, .comptime_int => @as(T, @floatFromInt(val)),
                    .float, .comptime_float => @as(T, @floatCast(val)),
                    else => @compileError("Invalid type."),
                },
                else => @compileError("Invalid type."),
            },
            .int, .comptime_int => switch (I1) {
                .int, .comptime_int => @as(T, @splat(@intCast(val))),
                .float, .comptime_float => @as(T, @splat(@intFromFloat(val))),
                .vector => |v1| switch (@typeInfo(v1.child)) {
                    .int, .comptime_int => @as(T, @intCast(val)),
                    .float, .comptime_float => @as(T, @intFromFloat(val)),
                    else => @compileError("Invalid type."),
                },
                else => @compileError("Invalid type."),
            },
            else => @compileError("Unknown type."),
        },
        else => @as(T, val),
    };
}
