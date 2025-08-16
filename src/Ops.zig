const std = @import("std");

pub const Op = union(enum) {
    pub fn params(comptime self: @This()) []const Op {
        comptime {
            return &ActivePayload(self).params;
        }
    }

    pub fn name(comptime self: @This()) [:0]const u8 {
        comptime {
            return @TypeOf(ActivePayload(self)).name;
        }
    }

    pub fn opvalue(comptime self: @This()) @TypeOf(ActivePayload(self)) {
        comptime {
            return ActivePayload(self);
        }
    }

    pub fn eval(
        comptime self: @This(),
        vals: anytype,
    ) self.opvalue().evaluator(@TypeOf(vals), null).dtype {
        return self.evalWithVals(vals).result;
    }

    pub fn evalWithVals(
        comptime self: @This(),
        vals: anytype,
    ) blk: {
        const e = self.opvalue().evaluator(@TypeOf(vals), null);
        break :blk struct { result: e.dtype, vals: e.vals_input_t };
    } {
        const e0 = comptime self.opvalue().evaluator(@TypeOf(vals), null);
        const e = comptime self.opvalue().evaluator(e0.vals_input_t, null);
        var vals_cpy: e.vals_input_t = undefined;

        inline for (@typeInfo(@TypeOf(vals)).@"struct".fields) |f| {
            @field(vals_cpy, f.name) = @field(vals, f.name);
        }
        return .{ .result = e.eval(&vals_cpy), .vals = vals_cpy };
    }

    pub fn cExport(
        comptime self: @This(),
        comptime exname: [:0]const u8,
        comptime vals: type,
    ) type {
        comptime {
            const e0 = self.opvalue().evaluator(vals, null);
            const e1 = self.opvalue().evaluator(e0.vals_input_t, null);
            const og_inp = @typeInfo(e1.vals_input_t).@"struct";

            var fields: [og_inp.fields.len]std.builtin.Type.StructField = undefined;

            for (og_inp.fields, 0..) |f, i| {
                fields[i] = std.builtin.Type.StructField{
                    .name = f.name,
                    .type = f.type,
                    .default_value_ptr = null,
                    .is_comptime = false,
                    .alignment = 0,
                };
            }

            const ext_input_type = @Type(.{
                .@"struct" = .{
                    .is_tuple = false,
                    .layout = .@"extern",
                    .decls = &.{},
                    .fields = &fields,
                },
            });

            const e = self.opvalue().evaluator(ext_input_type, null);

            const ret = struct {
                pub const input_type = ext_input_type;

                pub fn eval(vals_struct: *const input_type) callconv(.c) e.dtype {
                    var vals_cpy = vals_struct.*;
                    return e.eval(&vals_cpy);
                }
            };

            @export(&ret.eval, .{ .linkage = .strong, .name = exname });
            return ret;
        }
    }

    Constant: Constant,
    Variable: Variable,
    Cast: Cast,
    Index: Index,
    Assign: Assign,
    Value: Value,

    Add: Add,
    Sub: Sub,
    Mul: Mul,
    Div: Div,
    Neg: Neg,

    pub fn constant(comptime n: anytype) Op {
        return Constant.init(.{}, struct {
            pub const value = n;
        });
    }

    pub fn variable(varname: []const u8) Op {
        return Variable.init(.{}, varname);
    }

    pub fn value(self: Op) Op {
        return Value.init(.{self}, undefined);
    }

    pub fn cast(self: Op) Op {
        return Cast.init(.{self}, null);
    }

    pub fn castTo(self: Op, dtype: type) Op {
        return Cast.init(.{self}, dtype);
    }

    pub fn index(a: Op, b: Op) Op {
        return Index.init(.{ a, b }, undefined);
    }

    pub fn assign(self: Op, varname: []const u8) Op {
        return Assign.init(.{self}, varname);
    }

    pub fn add(a: Op, b: Op) Op {
        return Add.init(.{ a, b }, undefined);
    }

    pub fn sub(a: Op, b: Op) Op {
        return Sub.init(.{ a, b }, undefined);
    }

    pub fn mul(a: Op, b: Op) Op {
        return Mul.init(.{ a, b }, undefined);
    }

    pub fn div(a: Op, b: Op) Op {
        return Div.init(.{ a, b }, undefined);
    }

    pub fn neg(self: Op) Op {
        return Neg.init(.{self}, undefined);
    }
};

const Constant = MakeOp(
    "Constant",
    0,
    type,
    struct {
        fn call(
            comptime types: [0]type,
            comptime parent: ?type,
            comptime vals: type,
            comptime args: type,
        ) [2]type {
            _ = parent;
            _ = types;
            // const t = if (parent) |p| p else @TypeOf(args.value);
            return .{ @TypeOf(args.value), vals };
        }
    }.call,
    struct {
        fn eval(
            comptime ret_type: type,
            comptime args_type: type,
            comptime vals_type: type,
            comptime args: args_type,
            comptime params: anytype,
            vals: *vals_type,
        ) ret_type {
            _ = vals;
            _ = params;
            return num_cast(ret_type, args.value);
        }
    },
);

const Value = MakeOp(
    "Value",
    1,
    void,
    struct {
        fn call(
            comptime types: [1]type,
            comptime parent: ?type,
            comptime vals: type,
            comptime _: anytype,
        ) [2]type {
            _ = parent;
            return .{ types[0], vals };
        }
    }.call,
    struct {
        fn eval(
            comptime ret_type: type,
            comptime args_type: type,
            comptime vals_type: type,
            comptime args: args_type,
            comptime params: [1]type,
            vals: *vals_type,
        ) ret_type {
            _ = args;
            return params[0].eval(vals);
        }
    },
);

const Variable = MakeOp(
    "Variable",
    0,
    []const u8,
    struct {
        fn call(
            types: [0]type,
            parent: ?type,
            comptime vals: type,
            comptime name: []const u8,
        ) [2]type {
            _ = parent;
            _ = types;
            const n = std.fmt.comptimePrint("{s}", .{name});
            // var t = @FieldType(vals, n);
            // switch (@typeInfo(t)) {
            //     .comptime_int, .comptime_float => t = parent orelse t,
            //     else => {},
            // }
            return .{ @FieldType(vals, n), vals };
        }
    }.call,
    struct {
        fn eval(
            comptime ret_type: type,
            comptime args_type: type,
            comptime vals_type: type,
            comptime args: args_type,
            comptime params: anytype,
            vals: *vals_type,
        ) ret_type {
            _ = params;
            const n = comptime std.fmt.comptimePrint("{s}", .{args});
            return @field(vals.*, n);
        }
    },
);

const Cast = MakeOp(
    "Cast",
    1,
    ?type,
    struct {
        fn call(
            comptime types: [1]type,
            comptime parent: ?type,
            comptime vals: type,
            comptime args: ?type,
        ) [2]type {
            _ = types;
            const t = if (parent) |p| p else args orelse void;
            return .{ t, vals };
        }
    }.call,
    struct {
        fn eval(
            comptime ret_type: type,
            comptime args_type: type,
            comptime vals_type: type,
            comptime args: args_type,
            comptime params: [1]type,
            vals: *vals_type,
        ) ret_type {
            _ = args;
            return num_cast(ret_type, params[0].eval(vals));
        }
    },
);

const Index = MakeOp(
    "Index",
    2,
    void,
    struct {
        fn call(
            comptime types: [2]type,
            comptime parent: ?type,
            comptime vals: type,
            comptime _: void,
        ) [2]type {
            _ = parent;
            return .{ std.meta.Elem(types[0]), vals };
        }
    }.call,
    struct {
        fn eval(
            comptime ret_type: type,
            comptime args_type: type,
            comptime vals_type: type,
            comptime args: args_type,
            comptime params: [2]type,
            vals: *vals_type,
        ) ret_type {
            _ = args;
            return params[0].eval(vals)[num_cast(usize, params[1].eval(vals))];
        }
    },
);

const Assign = MakeOp(
    "Assign",
    1,
    []const u8,
    struct {
        fn call(
            comptime types: [1]type,
            comptime parent: ?type,
            comptime vals: type,
            comptime args: []const u8,
        ) [2]type {
            _ = parent;
            return .{ types[0], addField(vals, types[0], args) };
        }
    }.call,
    struct {
        fn eval(
            comptime ret_type: type,
            comptime args_type: type,
            comptime vals_type: type,
            comptime args: args_type,
            comptime params: [1]type,
            vals: *vals_type,
        ) ret_type {
            const v = params[0].eval(vals);
            @field(vals, args) = v;
            return v;
        }
    },
);

const Add = MakeBinaryOp("Add", struct {
    inline fn call(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        return a + b;
    }
});

const Sub = MakeBinaryOp("Sub", struct {
    inline fn call(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        return a - b;
    }
});

const Mul = MakeBinaryOp("Mul", struct {
    inline fn call(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        return a * b;
    }
});

const Div = MakeBinaryOp("Div", struct {
    inline fn call(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        switch (@typeInfo(@TypeOf(b))) {
            .float, .comptime_float => return a / b,
            .int, .comptime_int => return @divTrunc(a, b),
            .vector => |v| return switch (@typeInfo(v.child)) {
                .float, .comptime_float => return a / b,
                .int, .comptime_int => return @divTrunc(a, b),
                else => @compileError("Invalid type."),
            },
            else => @compileError("Invalid type."),
        }
    }
});

const Neg = MakeUnaryOp("Neg", struct {
    inline fn call(a: anytype) @TypeOf(a) {
        return -a;
    }
});

extern fn exported_eval(*const anyopaque) f32;

test "Basic" {
    var v0: f32 = 0;
    v0 += 1;
    const a = Op.constant(@as(f32, 1));
    const b = Op.variable("b");
    const ans = a.add(b).eval(.{ .b = 2 });

    try std.testing.expectEqual(3, ans);

    var i: f32 = 0;
    i += 1;
    const c = Op.constant(@as(i32, 1)).cast().castTo(f32).cast().cast();
    const ans0 = c.add(b).neg().eval(.{ .b = i });

    try std.testing.expectEqual(-2, ans0);

    const d = Op.constant("hello");
    const ans1 = d.index(c.castTo(usize)).value().eval(.{});

    try std.testing.expectEqual('e', ans1);

    const e = Op.constant(@as(f32, 4));
    const ans2 = e.assign("e").eval(.{ .a = void });

    try std.testing.expectEqual(4, ans2);

    const eval_t = a.add(b).cExport("exported_eval", @TypeOf(.{ .b = @as(f32, 1) }));
    const data: eval_t.input_type = .{ .b = 2 };
    try std.testing.expectEqual(3, eval_t.eval(&data));
    try std.testing.expectEqual(3, exported_eval(&data));
}

//////////////////////////////////// Internal Impl /////////////////////////////

fn MakeUnaryOp(
    comptime tagname: []const u8,
    comptime eval_fn: type,
) type {
    return MakeOp(
        tagname,
        1,
        void,
        struct {
            fn call(
                types: [1]type,
                parent: ?type,
                comptime vals: type,
                comptime _: void,
            ) [2]type {
                _ = parent;
                return .{ types[0], vals };
            }
        }.call,
        struct {
            fn eval(
                comptime ret_type: type,
                comptime args_type: type,
                comptime vals_type: type,
                comptime args: args_type,
                comptime params: [1]type,
                vals: *vals_type,
            ) ret_type {
                _ = args;
                return @call(
                    .always_inline,
                    eval_fn.call,
                    .{params[0].eval(vals)},
                );
            }
        },
    );
}

fn MakeBinaryOp(
    comptime tagname: []const u8,
    comptime eval_fn: type,
) type {
    return MakeOp(
        tagname,
        2,
        void,
        struct {
            fn call(
                types: [2]type,
                parent: ?type,
                comptime vals: type,
                comptime _: void,
            ) [2]type {
                _ = parent;
                return .{ types[0], vals };
            }
        }.call,
        struct {
            fn eval(
                comptime ret_type: type,
                comptime args_type: type,
                comptime vals_type: type,
                comptime args: args_type,
                comptime params: [2]type,
                vals: *vals_type,
            ) ret_type {
                _ = args;
                return @call(
                    .always_inline,
                    eval_fn.call,
                    .{ params[0].eval(vals), params[1].eval(vals) },
                );
            }
        },
    );
}

fn MakeOp(
    comptime tagname: []const u8,
    n_params: comptime_int,
    comptime args_t: type,
    comptime type_fn: fn (
        types: [n_params]type,
        parent: ?type,
        comptime vals: type,
        comptime args: args_t,
    ) [2]type,
    comptime eval_fn: type,
) type {
    return struct {
        pub const name = std.fmt.comptimePrint("{s}", .{tagname});

        args: args_t = undefined,
        params: [n_params]Op = undefined,

        pub fn init(comptime params: [n_params]Op, comptime args: args_t) Op {
            comptime {
                return opFromPayload(@This(){
                    .args = args,
                    .params = params,
                });
            }
        }

        pub fn evaluator(comptime self: @This(), comptime vals_t: type, comptime parent: ?type) type {
            comptime {
                var new_vals = vals_t;
                var types: [n_params]type = undefined;
                var evals_: [n_params]type = undefined;

                for (0..n_params) |i| {
                    evals_[i] = self.params[i].opvalue().evaluator(new_vals, null);
                    types[i] = evals_[i].dtype;
                    new_vals = evals_[i].vals_input_t;
                }

                var ext_t = type_fn(
                    types,
                    parent,
                    new_vals,
                    self.args,
                );

                var hascmpt = false;
                var non_comp_t: ?type = ext_t[0];

                for (0..types.len) |i| {
                    switch (@typeInfo(types[i])) {
                        // .comptime_int, .comptime_float => hascmpt = true,
                        .void => hascmpt = true,
                        else => non_comp_t = types[i],
                    }
                }

                if (hascmpt) {
                    if (non_comp_t) |nt| {
                        for (0..types.len) |i| {
                            switch (@typeInfo(types[i])) {
                                // .comptime_int, .comptime_float => types[i] = nt,
                                .void => types[i] = nt,
                                else => {},
                            }
                        }

                        for (0..n_params) |i| {
                            evals_[i] = self.params[i].opvalue().evaluator(new_vals, nt);
                            types[i] = evals_[i].dtype;
                            new_vals = evals_[i].vals_input_t;
                        }

                        ext_t = type_fn(
                            types,
                            parent,
                            new_vals,
                            self.args,
                        );
                    }
                }

                const final_t = ext_t;
                const evals = evals_;

                return struct {
                    pub const dtype = final_t[0];
                    pub const vals_input_t = final_t[1];

                    inline fn eval(vals: *vals_input_t) dtype {
                        return @call(.always_inline, eval_fn.eval, .{
                            dtype,
                            args_t,
                            vals_input_t,
                            comptime self.args,
                            evals,
                            vals,
                        });
                    }
                };
            }
        }
    };
}

fn ActivePayload(v: anytype) switch (@typeInfo(@TypeOf(v))) {
    .pointer => *@FieldType(@TypeOf(v.*), @tagName(std.meta.activeTag(v.*))),
    else => @FieldType(@TypeOf(v), @tagName(std.meta.activeTag(v))),
} {
    return switch (@typeInfo(@TypeOf(v))) {
        .pointer => &@field(v, @tagName(std.meta.activeTag(v.*))),
        else => @field(v, @tagName(std.meta.activeTag(v))),
    };
}

fn opFromPayload(v: anytype) Op {
    return @unionInit(Op, @TypeOf(v).name, v);
}

fn addField(comptime T: type, comptime fieldType: type, name: []const u8) type {
    comptime {
        const has_field = @hasField(T, name);
        if (has_field and fieldType != @FieldType(T, name))
            @compileError("Cannot change type");

        const FT = switch (@typeInfo(fieldType)) {
            .comptime_int, .comptime_float => if (has_field) @FieldType(T, name) else f32,
            else => fieldType,
        };

        const new_field = std.builtin.Type.StructField{
            .name = std.fmt.comptimePrint("{s}", .{name}),
            .type = FT,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = 0,
        };

        const inf = @typeInfo(T).@"struct";
        const prev_fields = inf.fields;
        var fields: [prev_fields.len + if (has_field) 0 else 1]std.builtin.Type.StructField = undefined;

        for (prev_fields, 0..) |f, i| fields[i] = .{
            .name = f.name,
            .type = if (has_field and std.mem.eql(u8, f.name, name)) FT else f.type,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = 0,
        };

        if (!has_field) {
            fields[prev_fields.len] = new_field;
        }

        return @Type(.{
            .@"struct" = .{
                .is_tuple = inf.is_tuple,
                .layout = inf.layout,
                .decls = &.{},
                .fields = &fields,
            },
        });
    }
}

inline fn num_cast(comptime T: type, val: anytype) T {
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
        else => @compileError("Unknown type."),
    };
}
