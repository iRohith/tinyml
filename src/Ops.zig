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

    const Field = struct { []const u8, type };

    fn structToFields(comptime vals: type) []Field {
        comptime {
            const fields = @typeInfo(vals).@"struct".fields;
            var vals_t: [fields.len]Field = undefined;

            for (fields, 0..) |f, i| {
                vals_t[i] = .{ f.name, f.type };
            }

            return &vals_t;
        }
    }

    pub fn eval(
        comptime self: @This(),
        vals: anytype,
    ) self.evaluator(structToFields(@TypeOf(vals))).dtype {
        const e = self.evaluator(structToFields(@TypeOf(vals)));
        var data: e.input_type = std.mem.zeroes(e.input_type);

        inline for (@typeInfo(@TypeOf(vals)).@"struct".fields) |f| {
            @field(data.vals, f.name) = @field(vals, f.name);
        }

        e.eval(&data);

        return data.result;
    }

    pub fn evalWithVals(
        comptime self: @This(),
        vals: anytype,
    ) self.evaluator(structToFields(@TypeOf(vals))).input_type {
        const e = self.evaluator(structToFields(@TypeOf(vals)));
        var data: e.input_type = std.mem.zeroes(e.input_type);

        inline for (@typeInfo(@TypeOf(vals)).@"struct".fields) |f| {
            @field(data.vals, f.name) = @field(vals, f.name);
        }

        e.eval(&data);

        return data;
    }

    pub fn evaluator(
        comptime self: @This(),
        comptime vals: []const Field,
    ) type {
        comptime {
            const e0 = self.opvalue().evaluator(blk: {
                var fields: [vals.len]std.builtin.Type.StructField = undefined;

                for (vals, 0..) |v, i| {
                    fields[i] = std.builtin.Type.StructField{
                        .name = std.fmt.comptimePrint("{s}", .{v[0]}),
                        .type = v[1],
                        .default_value_ptr = null,
                        .is_comptime = false,
                        .alignment = 0,
                    };
                }

                break :blk @Type(.{
                    .@"struct" = .{
                        .is_tuple = false,
                        .layout = .auto,
                        .decls = &.{},
                        .fields = &fields,
                    },
                });
            }, null);
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
                pub const dtype = e.dtype;
                pub const input_type = extern struct {
                    result: dtype = undefined,
                    vals: e.vals_input_t,
                };

                pub fn eval(output: *input_type) callconv(.c) void {
                    output.result = e.eval(&(output.vals));
                }
            };

            return ret;
        }
    }

    Constant: Constant,
    Variable: Variable,
    Cast: Cast,
    Index: Index,
    Assign: Assign,

    Void: Void,
    Block: Block,
    IfElse: IfElse,
    WhileLoop: WhileLoop,
    WhileLoopIndexed: WhileLoopIndexed,
    For: For,
    ForRange: ForRange,

    Add: Add,
    Sub: Sub,
    Mul: Mul,
    Div: Div,
    Neg: Neg,

    Eq: Eq,
    Neq: Neq,
    And: And,
    Or: Or,
    Not: Not,
    Lt: Lt,
    Lte: Lte,
    Gt: Gt,
    Gte: Gte,

    AND: AND,
    OR: OR,
    XOR: XOR,
    NOT: NOT,

    pub fn void_() Op {
        return Void.init(.{}, undefined);
    }

    pub fn constant(comptime n: anytype) Op {
        return Constant.init(.{}, struct {
            pub const value = n;
        });
    }

    pub fn variable(varname: []const u8) Op {
        return Variable.init(.{}, varname);
    }

    pub fn cast(self: Op) Op {
        return Cast.init(.{self}, @as(?type, null));
    }

    pub fn castTo(self: Op, dtype: type) Op {
        return Cast.init(.{self}, @as(?type, dtype));
    }

    pub fn index(a: Op, b: Op) Op {
        return Index.init(.{ a, b }, undefined);
    }

    pub fn assign(self: Op, varname: []const u8, dtype_: ?type) Op {
        return Assign.init(.{self}, .{
            .name = varname,
            .dtype = dtype_,
        });
    }

    pub fn block(ops: []const Op) Op {
        comptime {
            return Block.init(.{}, ops);
        }
    }

    pub fn if_else(cond: Op, then_: Op, else_: Op) Op {
        return IfElse.init(.{ cond, then_, else_ }, undefined);
    }

    pub fn while_(cond: Op, then_: Op) Op {
        return WhileLoop.init(.{ cond, then_ }, undefined);
    }

    pub fn while_indexed(iname: []const u8, cond: Op, then_: Op) Op {
        return WhileLoopIndexed.init(.{ cond, then_ }, iname);
    }

    pub fn for_(init: ?Op, cond: Op, next: ?Op, then_: Op) Op {
        return For.init(.{ init orelse Op.void_(), cond, next orelse Op.void_(), then_ }, undefined);
    }

    pub fn for_range(iname: []const u8, start: ?Op, stop: Op, step: ?Op, cond: ?Op, then_: Op) Op {
        return ForRange.init(.{
            start orelse Op.constant(0),
            stop,
            step orelse Op.constant(1),
            cond orelse Op.constant(true),
            then_,
        }, iname);
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

    pub fn eq(a: Op, b: Op) Op {
        return Eq.init(.{ a, b }, undefined);
    }

    pub fn neq(a: Op, b: Op) Op {
        return Neq.init(.{ a, b }, undefined);
    }

    pub fn and_(a: Op, b: Op) Op {
        return And.init(.{ a, b }, undefined);
    }

    pub fn or_(a: Op, b: Op) Op {
        return Or.init(.{ a, b }, undefined);
    }

    pub fn not(self: Op) Op {
        return Not.init(.{self}, undefined);
    }

    pub fn lt(a: Op, b: Op) Op {
        return Lt.init(.{ a, b }, undefined);
    }

    pub fn lte(a: Op, b: Op) Op {
        return Lte.init(.{ a, b }, undefined);
    }

    pub fn gt(a: Op, b: Op) Op {
        return Gt.init(.{ a, b }, undefined);
    }

    pub fn gte(a: Op, b: Op) Op {
        return Gte.init(.{ a, b }, undefined);
    }

    pub fn AND_(a: Op, b: Op) Op {
        return AND.init(.{ a, b }, undefined);
    }

    pub fn OR_(a: Op, b: Op) Op {
        return OR.init(.{ a, b }, undefined);
    }

    pub fn XOR_(a: Op, b: Op) Op {
        return XOR.init(.{ a, b }, undefined);
    }

    pub fn NOT_(self: Op) Op {
        return NOT.init(.{self}, undefined);
    }
};

const Void = MakeSimpleOp("Void", 0, struct {
    inline fn call(comptime T: type, comptime _: [0]type, _: anytype) T {
        return undefined;
    }
}, null);

const Constant = MakeOp(
    "Constant",
    0,
    type,
    struct {
        fn call(
            comptime op: Op,
            comptime types: [0]type,
            comptime parent: ?type,
            comptime vals: type,
            comptime args: type,
        ) [3]type {
            _ = op;
            _ = types;
            return .{ switch (@typeInfo(@TypeOf(args.value))) {
                .comptime_int, .comptime_float, .void, .null, .undefined => parent orelse @TypeOf(args.value),
                else => @TypeOf(args.value),
            }, vals, void };
        }
    },
    struct {
        fn eval(
            comptime op: Op,
            comptime ret_type: type,
            comptime vals_type: type,
            comptime args: type,
            comptime extra: type,
            comptime params: anytype,
            vals: *vals_type,
        ) ret_type {
            _ = op;
            _ = extra;
            _ = vals;
            _ = params;
            return switch (@typeInfo(ret_type)) {
                .int, .float, .vector => cast(ret_type, args.value),
                else => args.value,
            };
        }
    },
);

const Variable = MakeOp(
    "Variable",
    0,
    []const u8,
    struct {
        fn call(
            comptime op: Op,
            comptime types: [0]type,
            comptime parent: ?type,
            comptime vals: type,
            comptime args: []const u8,
        ) [3]type {
            _ = op;
            _ = types;
            _ = parent;
            const n = std.fmt.comptimePrint("{s}", .{args});
            return .{ if (@hasField(vals, n)) @FieldType(vals, n) else void, vals, void };
        }
    },
    struct {
        fn eval(
            comptime op: Op,
            comptime ret_type: type,
            comptime vals_type: type,
            comptime args: []const u8,
            comptime extra: type,
            comptime params: anytype,
            vals: *vals_type,
        ) ret_type {
            _ = op;
            _ = extra;
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
            comptime op: Op,
            comptime types: [1]type,
            comptime parent: ?type,
            comptime vals: type,
            comptime args: ?type,
        ) [3]type {
            _ = op;
            _ = types;
            const t = if (parent) |p| p else args orelse void;
            return .{ t, vals, void };
        }
    },
    struct {
        fn eval(
            comptime op: Op,
            comptime ret_type: type,
            comptime vals_type: type,
            comptime args: ?type,
            comptime extra: type,
            comptime params: [1]type,
            vals: *vals_type,
        ) ret_type {
            _ = op;
            _ = extra;
            _ = args;
            return cast(ret_type, params[0].eval(vals));
        }
    },
);

const Index = MakeOp(
    "Index",
    2,
    void,
    struct {
        fn call(
            comptime op: Op,
            comptime types: [2]type,
            comptime parent: ?type,
            comptime vals: type,
            comptime args: void,
        ) [3]type {
            _ = op;
            _ = parent;
            _ = args;
            return .{ std.meta.Elem(types[0]), vals, void };
        }
    },
    struct {
        fn eval(
            comptime op: Op,
            comptime ret_type: type,
            comptime vals_type: type,
            comptime args: void,
            comptime extra: type,
            comptime params: [2]type,
            vals: *vals_type,
        ) ret_type {
            _ = op;
            _ = extra;
            _ = args;
            return params[0].eval(vals)[cast(usize, params[1].eval(vals))];
        }
    },
);

const Assign = MakeOp(
    "Assign",
    1,
    struct { name: []const u8, dtype: ?type },
    struct {
        fn call(
            comptime op: Op,
            comptime types: [1]type,
            comptime parent: ?type,
            comptime vals: type,
            comptime args: anytype,
        ) [3]type {
            _ = op;
            _ = parent;
            const t = args.dtype orelse types[0];
            return .{ t, addField(vals, t, args.name), void };
        }
    },
    struct {
        fn eval(
            comptime op: Op,
            comptime ret_type: type,
            comptime vals_type: type,
            comptime args: anytype,
            comptime extra: type,
            comptime params: [1]type,
            vals: *vals_type,
        ) ret_type {
            _ = op;
            _ = extra;
            const v = params[0].eval(vals);
            @field(vals, args.name) = v;
            return v;
        }
    },
);

const Add = MakeSimpleOp("Add", 2, struct {
    inline fn call(comptime T: type, comptime params: [2]type, vals: anytype) T {
        return params[0].eval(vals) + params[1].eval(vals);
    }
}, null);

const Sub = MakeSimpleOp("Sub", 2, struct {
    inline fn call(comptime T: type, comptime params: [2]type, vals: anytype) T {
        return params[0].eval(vals) - params[1].eval(vals);
    }
}, null);

const Mul = MakeSimpleOp("Mul", 2, struct {
    inline fn call(comptime T: type, comptime params: [2]type, vals: anytype) T {
        return params[0].eval(vals) * params[1].eval(vals);
    }
}, null);

const Div = MakeSimpleOp("Div", 2, struct {
    inline fn call(comptime T: type, comptime params: [2]type, vals: anytype) T {
        const a = params[0].eval(vals);
        const b = params[1].eval(vals);
        switch (@typeInfo(T)) {
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
}, null);

const Neg = MakeSimpleOp("Neg", 1, struct {
    inline fn call(comptime T: type, comptime params: [1]type, vals: anytype) T {
        return -params[0].eval(vals);
    }
}, null);

const Eq = MakeSimpleOp("Eq", 2, struct {
    inline fn call(comptime _: type, comptime params: [2]type, vals: anytype) bool {
        return std.meta.eql(params[0].eval(vals), params[1].eval(vals));
    }
}, bool);

const Neq = MakeSimpleOp("Neq", 2, struct {
    inline fn call(comptime _: type, comptime params: [2]type, vals: anytype) bool {
        return !std.meta.eql(params[0].eval(vals), params[1].eval(vals));
    }
}, bool);

const And = MakeSimpleOp("And", 2, struct {
    inline fn call(comptime _: type, comptime params: [2]type, vals: anytype) bool {
        return params[0].eval(vals) and params[1].eval(vals);
    }
}, bool);

const Or = MakeSimpleOp("Or", 2, struct {
    inline fn call(comptime _: type, comptime params: [2]type, vals: anytype) bool {
        return params[0].eval(vals) or params[1].eval(vals);
    }
}, bool);

const Not = MakeSimpleOp("Not", 1, struct {
    inline fn call(comptime _: type, comptime params: [1]type, vals: anytype) bool {
        return !params[0].eval(vals);
    }
}, bool);

const Lt = MakeSimpleOp("Lt", 2, struct {
    inline fn call(comptime _: type, comptime params: [2]type, vals: anytype) bool {
        return params[0].eval(vals) < params[1].eval(vals);
    }
}, bool);

const Lte = MakeSimpleOp("Lte", 2, struct {
    inline fn call(comptime _: type, comptime params: [2]type, vals: anytype) bool {
        return params[0].eval(vals) <= params[1].eval(vals);
    }
}, bool);

const Gt = MakeSimpleOp("Gt", 2, struct {
    inline fn call(comptime _: type, comptime params: [2]type, vals: anytype) bool {
        return params[0].eval(vals) > params[1].eval(vals);
    }
}, bool);

const Gte = MakeSimpleOp("Gte", 2, struct {
    inline fn call(comptime _: type, comptime params: [2]type, vals: anytype) bool {
        return params[0].eval(vals) >= params[1].eval(vals);
    }
}, bool);

const AND = MakeSimpleOp("AND", 2, struct {
    inline fn call(comptime T: type, comptime params: [2]type, vals: anytype) T {
        return params[0].eval(vals) & params[1].eval(vals);
    }
}, null);

const OR = MakeSimpleOp("OR", 2, struct {
    inline fn call(comptime T: type, comptime params: [2]type, vals: anytype) T {
        return params[0].eval(vals) | params[1].eval(vals);
    }
}, null);

const XOR = MakeSimpleOp("XOR", 2, struct {
    inline fn call(comptime T: type, comptime params: [2]type, vals: anytype) T {
        return params[0].eval(vals) ^ params[1].eval(vals);
    }
}, null);

const NOT = MakeSimpleOp("NOT", 1, struct {
    inline fn call(comptime T: type, comptime params: [1]type, vals: anytype) T {
        return ~params[0].eval(vals);
    }
}, null);

extern fn exported_eval(*anyopaque) void;

test "Basic" {
    var v0: f32 = 0;
    v0 += 1;
    const a = Op.constant(@as(f32, 1));
    const b = Op.variable("b");
    const ans = a.add(b).eval(.{ .b = @as(f32, 2) });

    try std.testing.expectEqual(3, ans);

    var i: f32 = 0;
    i += 1;
    const c = Op.constant(@as(i32, 1)).cast().castTo(f32).cast().cast();
    const ans0 = c.add(b).neg().eval(.{ .b = i });

    try std.testing.expectEqual(-2, ans0);

    const d = Op.constant("hello");
    const ans1 = d.index(c.castTo(usize)).eval(.{});

    try std.testing.expectEqual('e', ans1);

    const e = Op.constant(@as(f32, 4));
    const ans2 = e.assign("e", null).evalWithVals(.{});
    try std.testing.expectEqual(4, ans2.result);
    try std.testing.expectEqual(4, ans2.vals.e);

    const eval_t = a.add(b).evaluator(&.{.{ "b", f32 }});
    var data: eval_t.input_type = .{ .vals = .{ .b = 2 } };
    eval_t.eval(&data);
    try std.testing.expectEqual(3, data.result);

    @export(&eval_t.eval, .{ .linkage = .strong, .name = "exported_eval" });
    data.result = 500;
    exported_eval(&data);
    try std.testing.expectEqual(3, data.result);

    try std.testing.expect(Op.eq(e, e).eval(.{}));
    try std.testing.expect(Op.neq(c, e).eval(.{}));
    try std.testing.expect(Op.eq(c, e).not().eval(.{}));
    try std.testing.expect(Op.and_(Op.eq(e, e), Op.eq(e, e)).eval(.{}));
    try std.testing.expect(Op.or_(Op.eq(e, e), Op.eq(c, e)).eval(.{}));

    try std.testing.expectEqual(1 < 4, Op.lt(c, e).eval(.{}));
    try std.testing.expectEqual(1 <= 4, Op.lte(c, e).eval(.{}));
    try std.testing.expectEqual(4 > 1, Op.gt(e, c).eval(.{}));
    try std.testing.expectEqual(4 >= 1, Op.gte(e, c).eval(.{}));

    try std.testing.expectEqual(1 & 4, Op.AND_(c.castTo(i32), e.castTo(i32)).eval(.{}));
    try std.testing.expectEqual(1 | 4, Op.OR_(c.castTo(i32), e.castTo(i32)).eval(.{}));
    try std.testing.expectEqual(1 ^ 4, Op.XOR_(c.castTo(i32), e.castTo(i32)).eval(.{}));
    try std.testing.expectEqual(~@as(i32, 1), Op.NOT_(c.castTo(i32)).eval(.{}));
}

//////////////////////////////////// Control flow /////////////////////////////

const Block = MakeOp(
    "Block",
    0,
    []const Op,
    struct {
        fn call(
            comptime op: Op,
            comptime types: [0]type,
            comptime parent: ?type,
            comptime vals: type,
            comptime args: []const Op,
        ) [3]type {
            _ = op;
            comptime {
                _ = types;
                var new_vals: type = vals;
                var ret_type: type = void;

                for (args) |op_| {
                    new_vals = op_.opvalue().evaluator(new_vals, parent).vals_input_t;
                }

                var evals_: [args.len]type = undefined;

                for (args, 0..) |op_, i| {
                    const e = op_.opvalue().evaluator(new_vals, parent);
                    ret_type = e.dtype;
                    evals_[i] = e;
                }

                return .{ ret_type, new_vals, struct {
                    pub const dtype = ret_type;
                    pub const evals = evals_;
                } };
            }
        }
    },
    struct {
        fn eval(
            comptime op: Op,
            comptime ret_type: type,
            comptime vals_type: type,
            comptime args: []const Op,
            comptime extra: type,
            comptime params: [0]type,
            vals: *vals_type,
        ) ret_type {
            _ = op;
            _ = args;
            _ = params;

            inline for (0..extra.evals.len - 1) |i| {
                _ = extra.evals[i].eval(vals);
            }

            return extra.evals[extra.evals.len - 1].eval(vals);
        }
    },
);

const IfElse = MakeSimpleOp("IfElse", 3, struct {
    inline fn call(comptime T: type, comptime params: [3]type, vals: anytype) T {
        return if (params[0].eval(vals)) params[1].eval(vals) else params[2].eval(vals);
    }
}, null);

const WhileLoop = MakeSimpleOp("WhileLoop", 2, struct {
    inline fn call(comptime T: type, comptime params: [2]type, vals: anytype) T {
        var res: T = undefined;
        while (params[0].eval(vals)) res = params[1].eval(vals);
        return res;
    }
}, null);

const WhileLoopIndexed = MakeOp(
    "WhileLoopIndexed",
    2,
    []const u8,
    struct {
        fn call(
            comptime op: Op,
            comptime types: [2]type,
            comptime parent: ?type,
            comptime vals: type,
            comptime args: []const u8,
        ) [3]type {
            _ = op;
            _ = parent;
            const n = std.fmt.comptimePrint("{s}", .{args});

            return .{
                types[1],
                addField(vals, usize, n),
                void,
            };
        }
    },
    struct {
        fn eval(
            comptime op: Op,
            comptime ret_type: type,
            comptime vals_type: type,
            comptime args: []const u8,
            comptime extra: type,
            comptime params: [2]type,
            vals: *vals_type,
        ) ret_type {
            _ = op;
            _ = extra;
            const n = comptime std.fmt.comptimePrint("{s}", .{args});

            @field(vals, n) = 0;
            var res: ret_type = undefined;
            while (params[0].eval(vals)) {
                res = params[1].eval(vals);
                @field(vals, n) += 1;
            }
            return res;
        }
    },
);

const For = MakeSimpleOp("For", 4, struct {
    inline fn call(comptime T: type, comptime params: [4]type, vals: anytype) T {
        var res: T = undefined;
        _ = params[0].eval(vals);
        while (params[1].eval(vals)) {
            res = params[3].eval(vals);
            _ = params[2].eval(vals);
        }
        return res;
    }
}, null);

const ForRange = MakeOp(
    "ForRange",
    5,
    []const u8,
    struct {
        fn call(
            comptime op: Op,
            comptime types: [5]type,
            comptime parent: ?type,
            comptime vals: type,
            comptime args: []const u8,
        ) [3]type {
            _ = op;
            _ = parent;
            const n = std.fmt.comptimePrint("{s}", .{args});

            return .{
                types[4],
                addField(vals, types[1], n),
                void,
            };
        }
    },
    struct {
        fn eval(
            comptime op: Op,
            comptime ret_type: type,
            comptime vals_type: type,
            comptime args: []const u8,
            comptime extra: type,
            comptime params: [5]type,
            vals: *vals_type,
        ) ret_type {
            _ = op;
            _ = extra;
            const n = comptime std.fmt.comptimePrint("{s}", .{args});

            const start = params[0].eval(vals);
            const stop = params[1].eval(vals);
            const step = params[2].eval(vals);

            @field(vals, n) = start;
            var res: ret_type = undefined;
            while (@field(vals, n) < stop and params[3].eval(vals)) {
                res = params[4].eval(vals);
                @field(vals, n) += step;
            }
            return res;
        }
    },
);

test "Control Flow" {
    var v: u32 = 0;
    v += 10;
    const a = Op.variable("a");
    const b = Op.variable("b");
    {
        const blk = Op.block(&.{ a, Op.assign(Op.constant(2).mul(b), "c", null), b });
        const ans = blk.evalWithVals(.{ .a = v, .b = v * 2 });

        try std.testing.expectEqual(v * 2, ans.result);
        try std.testing.expectEqual(v * 2 * 2, ans.vals.c);
    }
    {
        var bv = false;
        bv = !bv;

        const blk = Op.if_else(Op.variable("bv"), Op.assign(Op.constant(2).mul(b), "c", null), Op.void_());
        const ans = blk.evalWithVals(.{ .a = v, .b = v * 2, .bv = bv });

        try std.testing.expectEqual(if (bv) v * 2 * 2 else v * 2, ans.result);
        try std.testing.expectEqual(v * 2 * 2, ans.vals.c);
    }
    {
        const i = Op.variable("i");
        const j = Op.variable("j");

        const cond = Op.lt(Op.assign(i.add(Op.constant(1)), "i", null), Op.constant(5));
        const wloop = Op.while_(cond, Op.block(&.{
            Op.assign(j.add(Op.constant(1)), "j", null),
            i,
        }));
        try std.testing.expectEqual(4, wloop.eval(.{
            .i = @as(u32, 0),
            .j = @as(u32, 0),
        }));

        const cond1 = Op.gte(Op.assign(i.sub(Op.constant(1)), "i", null), Op.constant(0));
        const wloop1 = Op.while_(cond1, Op.block(&.{
            Op.assign(j.add(Op.constant(1)), "j", null),
            i,
        }));
        try std.testing.expectEqual(0, wloop1.eval(.{
            .i = @as(i32, 5),
            .j = @as(i32, 0),
        }));

        const cond2 = Op.lte(i, Op.constant(50));
        const wloop2 = Op.while_indexed("i", cond2, Op.block(&.{i}));
        try std.testing.expectEqual(50, wloop2.eval(.{}));
    }
    {
        const i = Op.variable("i");
        const loop = Op.for_(
            Op.assign(Op.constant(0), "i", f32),
            i.lt(Op.constant(5)),
            Op.assign(i.add(Op.constant(1)), "i", null),
            i,
        );
        try std.testing.expectEqual(4, comptime loop.eval(.{}));
    }
    {
        const i = Op.variable("i");
        const loop = Op.for_range("i", null, Op.constant(@as(f32, 10)), Op.constant(2), null, i);
        try std.testing.expectEqual(8, comptime loop.eval(.{}));
    }
}

//////////////////////////////////// Internal Impl /////////////////////////////

fn MakeSimpleOp(
    comptime tagname: []const u8,
    comptime n_params: comptime_int,
    comptime eval_fn: type,
    comptime ret: ?type,
) type {
    return MakeOp(
        tagname,
        n_params,
        type,
        struct {
            fn call(
                comptime op: Op,
                comptime types: [n_params]type,
                comptime parent: ?type,
                comptime vals: type,
                comptime args: type,
            ) [3]type {
                _ = op;
                _ = args;
                return .{ ret orelse (if (n_params > 0) types[n_params - 1] else (parent orelse void)), vals, void };
            }
        },
        struct {
            fn eval(
                comptime op: Op,
                comptime ret_type: type,
                comptime vals_type: type,
                comptime args: type,
                comptime extra: type,
                comptime params: [n_params]type,
                vals: *vals_type,
            ) ret_type {
                _ = op;
                _ = extra;
                _ = args;
                return @call(.always_inline, eval_fn.call, .{ ret_type, params, vals });
            }
        },
    );
}

fn MakeOp(
    comptime tagname: []const u8,
    n_params: comptime_int,
    comptime args_t: type,
    comptime type_fn: type,
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
                const op_ = opFromPayload(self);
                var new_vals = vals_t;
                var types: [n_params]type = undefined;
                var evals_: [n_params]type = undefined;

                for (0..n_params) |i| {
                    evals_[i] = self.params[i].opvalue().evaluator(new_vals, null);
                    types[i] = evals_[i].dtype;
                    new_vals = evals_[i].vals_input_t;
                }

                var ext_t = type_fn.call(
                    op_,
                    types,
                    parent,
                    new_vals,
                    self.args,
                );

                var hascmpt = false;
                var non_comp_t: ?type = ext_t[0];

                for (0..types.len) |i| {
                    switch (@typeInfo(types[i])) {
                        .void, .comptime_float, .comptime_int => hascmpt = true,
                        else => non_comp_t = types[i],
                    }
                }

                if (hascmpt) {
                    if (non_comp_t) |nt| {
                        for (0..types.len) |i| {
                            switch (@typeInfo(types[i])) {
                                .void, .comptime_float, .comptime_int => types[i] = nt,
                                else => {},
                            }
                        }

                        for (0..n_params) |i| {
                            evals_[i] = self.params[i].opvalue().evaluator(new_vals, nt);
                            types[i] = evals_[i].dtype;
                            new_vals = evals_[i].vals_input_t;
                        }

                        ext_t = type_fn.call(
                            op_,
                            types,
                            parent,
                            new_vals,
                            self.args,
                        );
                    }
                }

                return struct {
                    pub const op = op_;
                    pub const name = tagname;
                    pub const dtype = ext_t[0];
                    pub const vals_input_t = ext_t[1];

                    inline fn eval(vals: *vals_input_t) dtype {
                        return @call(.always_inline, eval_fn.eval, .{
                            op,
                            dtype,
                            vals_input_t,
                            self.args,
                            ext_t[2],
                            evals_,
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

fn addField(comptime T: type, comptime fieldType_: type, name: []const u8) type {
    comptime {
        const has_field = @hasField(T, name);
        const og_t = if (has_field) @FieldType(T, name) else void;
        var fieldType = fieldType_;

        if (has_field) {
            if (fieldType != og_t)
                switch (@typeInfo(fieldType_)) {
                    .comptime_int, .comptime_float => {
                        fieldType = og_t;
                    },
                    else => {},
                    // else => {
                    //     @compileLog(name, fieldType, og_t);
                    //     @compileError("Cannot change type");
                    // },
                }
            else
                return T;
        }

        const FT = switch (@typeInfo(fieldType)) {
            .comptime_int, .comptime_float => if (has_field) og_t else f32,
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

inline fn cast(comptime T: type, val: anytype) T {
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
