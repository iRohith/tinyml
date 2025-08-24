const std = @import("std");
const eql = std.mem.eql;
const cprint = std.fmt.comptimePrint;
const str = [:0]const u8;
const BuildContext = @import("BuildContext.zig").BuildContext;
const Refl = @import("Reflection.zig");
const OpDef = @import("OpDef.zig").OpDef;
const TypeHint = @import("OpDef.zig").TypeHint;
const DTypeFn = @import("OpDef.zig").DTypeFn;
const cast = @import("Util.zig").cast;

pub fn mk_const(bc: *BuildContext, comptime val: anytype) OpDef {
    return OpDef{
        .name = "const",
        .ctx = bc,
        .dtype = struct {
            fn call(_: TypeHint) ?type {
                return @TypeOf(val);
            }
        }.call,
        .eval_t = struct {
            pub fn call(
                ret_type: type,
                noalias _: anytype,
                _: anytype,
            ) ret_type {
                return val;
            }
        },
    };
}

pub fn mk_var(bc: *BuildContext, comptime name: str, comptime is_input: bool) OpDef {
    return OpDef{
        .name = "var",
        .ctx = bc,
        .dtype = struct {
            fn call(th: TypeHint) ?type {
                const field = th.ctx.getField(name);
                if (field) |f| {
                    if (f.dtype) |dt| {
                        return dt;
                    } else {
                        return null;
                    }
                } else {
                    th.ctx.addInput(name, if (is_input) "inputs" else "default", null, th.parent_t);
                    return th.parent_t;
                }
            }
        }.call,
        .eval_t = struct {
            pub fn call(
                ret_type: type,
                noalias tmp: anytype,
                _: anytype,
            ) ret_type {
                return Refl.get(&.{name}, tmp);
            }
        },
    };
}

pub fn mk_ref(bc: *BuildContext, comptime name: str, dtype: ?type, scope_: ?str) OpDef {
    const scope = scope_ orelse "default";
    return OpDef{
        .name = "ref",
        .ctx = bc,
        .dtype = struct {
            fn call(th: TypeHint) ?type {
                const dt: ?type = dtype orelse th.parent_t;
                const field = th.ctx.getField(name);
                if (field) |f| {
                    if (f.dtype) |fdt| {
                        return *fdt;
                    } else {
                        f.dtype = dt;
                        return if (dt) |t| *t else null;
                    }
                }

                th.ctx.addInput(name, scope, null, dt);
                return if (dt) |t| *t else null;
            }
        }.call,
        .eval_t = struct {
            pub fn call(
                ret_type: type,
                noalias tmp: anytype,
                _: anytype,
            ) ret_type {
                return Refl.getRef(&.{name}, tmp);
            }
        },
    };
}

pub fn mk_cast(op: OpDef, dtype: ?type) OpDef {
    const tname = cprint("{d}", .{op.ctx.state});
    op.ctx.state += 1;
    const dt_fn = op.dtype;
    return OpDef{
        .name = "cast",
        .ctx = op.ctx,
        .inputs = &.{op},
        .dtype = struct {
            fn call(th_: TypeHint) ?type {
                var th = th_;
                const t: ?type = dtype orelse th.parent_t;
                const field = th.ctx.getField(tname);
                if (field) |f| {
                    if (t) |_t| f.dtype = _t;
                    th.parent_t = f.dtype;
                    _ = dt_fn(th);
                    return f.dtype;
                } else th.ctx.addInput(tname, "build", null, t);
                th.parent_t = t;
                _ = dt_fn(th);
                return t;
            }
        }.call,
        .eval_t = struct {
            pub fn call(
                ret_type: type,
                noalias tmp: anytype,
                evals: anytype,
            ) ret_type {
                return cast(ret_type, evals[0].call(tmp));
            }
        },
    };
}

pub fn mk_assign(ref: OpDef, op_: OpDef) OpDef {
    const dt_fn = comptime op_.dtype;
    return OpDef{
        .name = "assign",
        .ctx = op_.ctx,
        .inputs = &.{ ref, op_ },
        .dtype = struct {
            fn call(th: TypeHint) ?type {
                if (dt_fn(th)) |dt| {
                    _ = dt;
                    return void;
                } else {
                    return void;
                }
            }
        }.call,
        .eval_t = struct {
            pub fn call(
                ret_type: type,
                noalias tmp: anytype,
                evals: anytype,
            ) ret_type {
                evals[0].call(tmp).* = evals[1].call(tmp);
            }
        },
    };
}

pub fn mk_simple(bc: *BuildContext, opname: str, ops_: []const ?OpDef, type_idx: ?usize, func: type) OpDef {
    comptime {
        var dt_fns: [ops_.len]?DTypeFn = undefined;
        var names: [ops_.len]str = undefined;
        for (ops_, 0..) |op_, i| {
            dt_fns[i] = if (op_) |op| op.dtype else null;
            names[i] = op_.?.name;
        }
        return OpDef{
            .name = opname,
            .ctx = bc,
            .inputs = ops_,
            .dtype = struct {
                fn findDtype(th_: TypeHint) ?type {
                    var th = th_;
                    if (type_idx) |tidx| {
                        if (dt_fns[tidx]) |dt_fn| {
                            if (dt_fn(th)) |dt| {
                                return dt;
                            }
                        }
                    } else {
                        var types: [dt_fns.len]?type = undefined;
                        var non_null_t: ?type = null;

                        for (dt_fns, 0..) |ndt_fn, i| {
                            types[i] = if (ndt_fn) |dt_fn| dt_fn(th) else null;
                            if (types[i]) |t| non_null_t = t;
                        }

                        th.parent_t = non_null_t;

                        if (non_null_t != null) {
                            for (dt_fns, 0..) |ndt_fn, i| {
                                types[i] = if (ndt_fn) |dt_fn| dt_fn(th) else null;
                                if (types[i]) |t| non_null_t = t;
                            }
                        }

                        return non_null_t;
                    }
                    return null;
                }
                fn call(th: TypeHint) ?type {
                    const fd = findDtype(th);
                    return fd orelse th.parent_t;
                }
            }.call,
            .eval_t = struct {
                pub fn call(
                    ret_type: type,
                    noalias tmp: anytype,
                    evals: anytype,
                ) ret_type {
                    return @call(.always_inline, func.call, .{ ret_type, tmp, evals });
                }
            },
        };
    }
}

pub fn mk_index(a_: OpDef, b_: OpDef) OpDef {
    comptime {
        const dt_fn = a_.dtype;
        return OpDef{
            .name = "index",
            .ctx = a_.ctx,
            .inputs = &.{ a_, b_ },
            .dtype = struct {
                fn call(th: TypeHint) ?type {
                    if (dt_fn(th)) |dt| {
                        return switch (@typeInfo(dt)) {
                            .pointer => |info| if (info.size == .one) *std.meta.Elem(info.child) else info.child,
                            else => @compileError(cprint("Expected array type, found '{}'", .{dt})),
                        };
                    }
                    return null;
                }
            }.call,
            .eval_t = struct {
                pub fn call(
                    ret_type: type,
                    noalias tmp: anytype,
                    evals: anytype,
                ) ret_type {
                    return switch (@typeInfo(ret_type)) {
                        .pointer => &(evals[0].call(tmp).*[evals[1].call(tmp)]),
                        else => evals[0].call(tmp)[evals[1].call(tmp)],
                    };
                }
            },
        };
    }
}

pub fn mk_loop_range(
    comptime iname: str,
    v: struct {
        start: ?OpDef = null,
        stop: OpDef,
        step: ?OpDef = null,
        body: OpDef,
    },
    scope_: ?str,
) OpDef {
    const scope = scope_ orelse "default";
    const s = v.start orelse mk_const(v.body.ctx, 0);
    return mk_simple(v.body.ctx, "loop_range", &.{
        mk_ref(v.body.ctx, iname, usize, scope),
        s,
        v.stop,
        v.step orelse mk_const(v.body.ctx, 1),
        v.body,
    }, 4, struct {
        inline fn call(
            ret_type: type,
            noalias tmp: anytype,
            evals: anytype,
        ) ret_type {
            const i = evals[0].call(tmp);
            const step = evals[3].call(tmp);
            const stop = evals[2].call(tmp);

            i.* = evals[1].call(tmp);

            var ret: ret_type = undefined;

            while (i.* < stop) {
                ret = evals[4].call(tmp);
                i.* += step;
            }

            return ret;
        }
    });
}

pub fn mk_add(a_: OpDef, b_: OpDef) OpDef {
    return mk_simple(a_.ctx, "add", &.{ a_, b_ }, null, struct {
        inline fn call(
            ret_type: type,
            noalias tmp: anytype,
            evals: anytype,
        ) ret_type {
            return evals[0].call(tmp) + evals[1].call(tmp);
        }
    });
}
