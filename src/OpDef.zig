const std = @import("std");
const eql = std.mem.eql;
const str = [:0]const u8;
const BuildContext = @import("BuildContext.zig").BuildContext;

pub const TypeHint = struct {
    ctx: *BuildContext = undefined,
    parent_t: ?type = null,
    sample_t: type = undefined,
    evals_t: []const type = undefined,
};

pub const DTypeFn = fn (TypeHint) ?type;

pub const OpDef = struct {
    name: str,
    ctx: *BuildContext,
    inputs: []const ?OpDef = &.{},
    dtype: DTypeFn = struct {
        fn call(_: TypeHint) ?type {
            @compileError("Not implemented");
        }
    }.call,
    eval_t: type = struct {
        fn call(
            ret_type: type,
            noalias tmp: anytype,
            evals: []const type,
        ) ret_type {
            _ = tmp;
            _ = evals;
            @compileError("Not implemented");
        }
    },

    pub fn evaluator(
        comptime self: OpDef,
        comptime type_sample: type,
        comptime callconv_: std.builtin.CallingConvention,
    ) type {
        return self._evaluator(type_sample, void, callconv_);
    }

    fn _traverse(
        comptime op: OpDef,
        comptime ctx: *BuildContext,
        comptime type_sample: type,
    ) struct { ?type, []type } {
        comptime {
            var evals: [op.inputs.len]type = undefined;
            for (op.inputs, 0..) |opi, i| {
                if (opi) |inp| {
                    evals[i] = if (inp._traverse(
                        ctx,
                        type_sample,
                    )[0]) |t| t else void;
                } else {
                    evals[i] = void;
                }
            }
            const dt = op.dtype(TypeHint{
                .ctx = ctx,
                .sample_t = type_sample,
                .evals_t = &evals,
            });
            if (op.ctx.build(false) == null) return .{ null, &evals };
            return .{ dt, &evals };
        }
    }

    fn _evaluator(
        comptime self: OpDef,
        comptime type_sample: type,
        comptime final_inp_t: ?type,
        comptime callconv_: std.builtin.CallingConvention,
    ) type {
        comptime {
            @setEvalBranchQuota(100_000);
            const eval_fn = self.eval_t.call;

            var dt = self._traverse(
                self.ctx,
                type_sample,
            );

            if (final_inp_t == void) {
                for (@typeInfo(type_sample).@"struct".fields) |f| {
                    const e = self.ctx.exists(f.name, null);
                    const scope = if (e[0]) self.ctx.locals[e[1]].name else "inputs";
                    self.ctx.addInput(f.name, scope, null, f.type);
                }

                dt = self._traverse(
                    self.ctx,
                    type_sample,
                );
            }

            if (final_inp_t == null) {
                return struct {
                    pub const _dtype: ?type = dt[0];
                };
            }

            const BT: type = self.ctx.build(false).?;
            var evals: [self.inputs.len]type = undefined;

            for (self.inputs, 0..) |opi, i| {
                if (opi) |inp| {
                    evals[i] = inp._evaluator(
                        type_sample,
                        final_inp_t,
                        callconv_,
                    );
                } else {
                    evals[i] = struct {
                        pub const _dtype: ?type = void;
                        pub const dtype = void;
                        inline fn call(_: anytype, noalias _: anytype, _: anytype) void {}
                    };
                }
            }

            const final_dt = dt[0].?;

            return struct {
                pub const dtype = final_dt;
                pub const _input_t = BT;
                pub const input_t = @FieldType(_input_t, "inputs");

                pub inline fn call(noalias tmp: *_input_t) dtype {
                    @setEvalBranchQuota(100_000);
                    return @call(
                        .always_inline,
                        eval_fn,
                        .{ dtype, tmp, evals },
                    );
                }

                pub fn ceval(input: *const input_t) callconv(callconv_) switch (@typeInfo(dtype)) {
                    .comptime_int => i64,
                    .comptime_float => f64,
                    else => dtype,
                } {
                    var inps: _input_t = undefined;
                    inps.inputs = input.*;
                    return call(&inps);
                }
            };
        }
    }
};
