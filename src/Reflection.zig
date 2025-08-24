const std = @import("std");
const eql = std.mem.eql;
const str = [:0]const u8;

fn ValueType(comptime T: type, comptime name: ?str) type {
    return switch (@typeInfo(T)) {
        .@"struct" => if (name) |n|
            ValueType(@FieldType(T, n), null)
        else
            return T,
        .pointer => |info| switch (info.size) {
            .one => ValueType(info.child, name),
            else => T,
        },
        .optional => |info| return ValueType(info.child, name),
        else => T,
    };
}

inline fn valueOf(noalias val: anytype, comptime name: ?str) ValueType(@TypeOf(val), name) {
    return switch (@typeInfo(@TypeOf(val))) {
        .@"struct" => if (name) |n|
            valueOf(@field(val, n), null)
        else
            val,
        .pointer => |info| if (info.size == .one) valueOf(val.*, name) else val,
        .optional => valueOf(val.?.*),
        else => val,
    };
}

fn RefType(comptime T: type, comptime name: ?str) type {
    return switch (@typeInfo(T)) {
        .pointer => |info| if (info.size == .one) switch (@typeInfo(info.child)) {
            .pointer => |info1| if (info1.size == .one)
                RefType(info.child, name)
            else
                (if (info1.is_const) *const info.child else *info.child),
            else => if (@typeInfo(info.child) != .@"struct" or name == null)
                T
            else
                RefType(if (info.is_const)
                    *const @FieldType(info.child, name.?)
                else
                    *@FieldType(info.child, name.?), null),
        } else T,
        .optional => |info| RefType(info.child, name),
        else => if (name) |n|
            RefType(*const @FieldType(T, n), null)
        else
            @compileError("Invalid"),
    };
}

inline fn refOf(noalias val: anytype, comptime name: ?str) RefType(@TypeOf(val), name) {
    return switch (@typeInfo(@TypeOf(val))) {
        .pointer => |info| if (info.size == .one) switch (@typeInfo(info.child)) {
            .pointer => |info1| if (info1.size == .one)
                refOf(val.*, name)
            else
                val,
            else => if (@typeInfo(info.child) != .@"struct" or name == null)
                val
            else
                refOf(&@field(val, name.?), null),
        } else val,
        .optional => refOf(val.?),
        else => if (name) |n|
            refOf(&@field(val, n), null)
        else
            @compileError("Invalid"),
    };
}

fn last(arr: anytype) std.meta.Elem(@TypeOf(arr)) {
    return arr[arr.len - 1];
}

fn ResolveTypePath(field_names: []const str, T: type) struct { []type, []str } {
    comptime {
        var types: [32]type = undefined;
        var names: [32]str = undefined;

        var i = 0;
        var currT = T;

        for (field_names) |n| {
            const ftn = FindTypeNested(n, currT);
            @memcpy(types[i .. i + ftn[0].len], ftn[0]);
            @memcpy(names[i .. i + ftn[1].len], ftn[1]);
            i += ftn[0].len;
            currT = last(ftn[0]);
        }

        return .{ types[0..i], names[0..i] };
    }
}

fn FindTypeNested(name: str, T: type) struct { []type, []str } {
    comptime {
        var names: [32]str = undefined;
        var types: [32]type = undefined;

        const ti = @typeInfo(ValueType(T, null));
        if (ti != .@"struct") return .{ types[0..0], names[0..0] };

        const F = ti.@"struct".fields;
        for (F) |f| {
            names[0] = f.name;
            if (eql(u8, f.name, name)) {
                types[0] = ValueType(f.type, null);
                return .{ types[0..1], names[0..1] };
            }
        }
        for (F) |f| {
            names[0] = f.name;
            const ftn = FindTypeNested(name, f.type);
            if (ftn[0].len > 0) {
                if (ftn[1].len > names.len) @compileError("Depth exceeded");
                @memcpy(names[1 .. ftn[1].len + 1], ftn[1]);
                @memcpy(types[1 .. ftn[0].len + 1], ftn[0]);
                types[0] = ValueType(f.type, null);
                return .{ types[0 .. ftn[0].len + 1], names[0 .. ftn[1].len + 1] };
            }
        }
        return .{ types[0..0], names[0..0] };
    }
}

fn FindNestedRefType(fields: []str, vals_t: type) type {
    const Fv = RefType(vals_t, fields[0]);
    if (fields.len == 1) {
        return Fv;
    } else {
        return FindNestedRefType(fields[1..], Fv);
    }
}

inline fn _get_field_ref(comptime ret_t: type, comptime fields: []str, noalias vals: anytype) ret_t {
    const Fv = refOf(vals, fields[0]);
    if (fields.len == 1) {
        return Fv;
    } else {
        return _get_field_ref(ret_t, fields[1..], Fv);
    }
}

pub inline fn getRef(
    comptime names: []const str,
    noalias vals: anytype,
) FindNestedRefType(ResolveTypePath(names, @TypeOf(vals))[1], @TypeOf(vals)) {
    const ft = ResolveTypePath(names, @TypeOf(vals));
    return _get_field_ref(FindNestedRefType(ft[1], @TypeOf(vals)), ft[1], vals);
}

pub inline fn get(
    comptime names: []const str,
    noalias vals: anytype,
) last(ResolveTypePath(names, @TypeOf(vals))[0]) {
    return getRef(names, vals).*;
}

pub inline fn set(comptime names: []const str, noalias vals: anytype, v: anytype) void {
    const ref = getRef(names, vals);
    ref.* = if (@typeInfo(@TypeOf(v)) == .@"fn")
        @call(.always_inline, v, .{ref.*})
    else
        v;
}
