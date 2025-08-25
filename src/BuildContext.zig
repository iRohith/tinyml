const std = @import("std");
const StructField = std.builtin.Type.StructField;
const eql = std.mem.eql;
const str = [:0]const u8;

const Field = struct { name: str, dtype: ?type };
const FieldArray = struct {
    variables: []Field = &.{},

    fn addVariable(comptime self: *FieldArray, comptime name: str, dtype: ?type) void {
        var vars: [self.variables.len + 1]Field = undefined;
        for (self.variables, 0..) |*v, i| {
            if (eql(u8, v.name, name)) {
                if (dtype) |dt| v.dtype = dt;
                return;
            }
            vars[i] = v.*;
        }
        vars[self.variables.len] = .{ .name = name, .dtype = dtype };
        self.variables = &vars;
    }

    fn indexOf(self: *const FieldArray, name: str) comptime_int {
        for (self.variables, 0..) |v, i| {
            if (eql(u8, v.name, name)) return i;
        }
        return -1;
    }

    fn build(self: FieldArray, is_extern: bool) ?type {
        comptime {
            var fields: [self.variables.len]StructField = undefined;
            for (self.variables, 0..) |v, i| {
                if (v.dtype == null) return null;
                var d: v.dtype.? = undefined;
                fields[i] = StructField{
                    .name = v.name,
                    .type = v.dtype.?,
                    .alignment = @alignOf(v.dtype.?),
                    .default_value_ptr = @ptrCast(&d),
                    .is_comptime = false,
                };
            }

            return @Type(std.builtin.Type{
                .@"struct" = std.builtin.Type.Struct{
                    .fields = &fields,
                    .layout = if (is_extern) .@"extern" else .auto,
                    .is_tuple = false,
                    .decls = &.{},
                },
            });
        }
    }
};

const Block = struct { name: str, parent: ?str = null, fields: FieldArray = .{} };

pub const BuildContext = struct {
    state: comptime_int = 0,
    locals: []Block,

    pub fn init() BuildContext {
        var locals = [3]Block{
            Block{ .name = "build", .parent = "none" },
            Block{ .name = "inputs", .parent = "none" },
            Block{ .name = "default", .parent = "inputs" },
        };
        return BuildContext{ .locals = &locals };
    }

    pub fn indexOf(self: *const BuildContext, name: str) comptime_int {
        for (self.locals, 0..) |b, i| {
            if (eql(u8, b.name, name)) return i;
        }
        return -1;
    }

    pub fn getField(self: *const BuildContext, name: str) ?*Field {
        for (self.locals) |b| {
            const i = b.fields.indexOf(name);
            if (i != -1) return &b.fields.variables[i];
        }
        return null;
    }

    pub fn exists(self: *const BuildContext, name: str, scope: ?str) struct { bool, comptime_int } {
        if (scope == null) {
            for (self.locals) |b| {
                const e = self.exists(name, b.name);
                if (e[0]) return e;
            }
            return .{ false, -1 };
        }

        const scope_name = scope.?;
        const i = self.indexOf(scope_name);
        if (i == -1) return .{ false, -1 };
        const b = self.locals[i];
        if (b.fields.indexOf(name) != -1) return .{ true, i };
        return if (eql(u8, scope_name, "default"))
            .{ false, -1 }
        else
            self.exists(name, b.parent orelse "default");
    }

    pub fn addInput(self: *BuildContext, name: str, scope: ?str, parent: ?str, dtype: ?type) void {
        comptime {
            const exists_ = self.exists(name, scope);

            if (exists_[0]) {
                if (parent) |p| self.locals[exists_[1]].parent = p;
                if (dtype) |dt| self.locals[exists_[1]].fields.addVariable(name, dt);
                return;
            }

            var locals: [self.locals.len + 1]Block = undefined;
            for (self.locals, 0..) |*b, i| {
                if (eql(u8, b.name, scope orelse "default")) {
                    if (parent) |p| b.parent = p;
                    b.fields.addVariable(name, dtype);
                    return;
                }

                locals[i] = b.*;
            }
            var fa = FieldArray{};
            fa.addVariable(name, dtype);
            locals[locals.len - 1] = Block{
                .name = scope orelse "default",
                .parent = parent,
                .fields = fa,
            };
            self.locals = &locals;
        }
    }

    pub fn build(self: BuildContext, is_extern: bool) ?type {
        var fields: [self.locals.len]Field = undefined;

        for (self.locals, 0..) |b, i| {
            if (i == 0) continue;
            fields[i] = .{ .name = b.name, .dtype = b.fields.build(is_extern) };
            // fields[i] = .{ .name = b.name, .dtype = b.fields.build(i == 1 or is_extern) };
        }

        return FieldArray.build(.{ .variables = fields[1..] }, is_extern);
    }
};
