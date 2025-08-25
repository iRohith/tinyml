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

pub fn mk_void(bc: *BuildContext, dtype: ?type) OpDef {
    return OpDef{
        .name = "void",
        .ctx = bc,
        .dtype = struct {
            fn call(_: TypeHint) ?type {
                return dtype;
            }
        }.call,
        .eval_t = struct {
            pub fn call(
                ret_type: type,
                noalias _: anytype,
                _: anytype,
            ) ret_type {
                return undefined;
            }
        },
    };
}

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
                const pt = if (th.parent_t) |p| Refl.ValueType(p, null) else null;
                if (field) |f| {
                    if (f.dtype) |dt| {
                        return Refl.ValueType(dt, null);
                    } else {
                        f.dtype = pt;
                        return f.dtype;
                    }
                } else {
                    th.ctx.addInput(name, if (is_input) "inputs" else "default", null, pt);
                    return pt;
                }
            }
        }.call,
        .eval_t = struct {
            pub fn call(
                ret_type: type,
                noalias tmp: anytype,
                _: anytype,
            ) ret_type {
                // switch (@typeInfo(ret_type)) {
                //     .pointer => |info| if (info.size == .one and !info.is_const)
                //         return Refl.getRef(&.{name}, tmp),
                //     else => {},
                // }
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

pub fn mk_val(refop: OpDef) OpDef {
    // if (!eql(u8, "ref", refop.name))
    //     @compileError(cprint("Expected ref, found '{s}'", .{refop.name}));
    const dt_fn = refop.dtype;
    return OpDef{
        .name = "val",
        .ctx = refop.ctx,
        .inputs = &.{refop},
        .dtype = struct {
            fn call(th: TypeHint) ?type {
                const dt_ = dt_fn(th);
                return if (dt_) |t| @typeInfo(t).pointer.child else null;
            }
        }.call,
        .eval_t = struct {
            pub fn call(
                ret_type: type,
                noalias tmp: anytype,
                evals: anytype,
            ) ret_type {
                return evals[0].call(tmp).*;
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

pub fn mk_len(op: OpDef) OpDef {
    const dt_fn = op.dtype;
    return OpDef{
        .name = "len",
        .ctx = op.ctx,
        .inputs = &.{op},
        .dtype = struct {
            fn call(th: TypeHint) ?type {
                _ = dt_fn(th);
                return usize;
            }
        }.call,
        .eval_t = struct {
            pub fn call(
                ret_type: type,
                noalias tmp: anytype,
                evals: anytype,
            ) ret_type {
                switch (@typeInfo(evals[0].dtype)) {
                    .vector => |info| {
                        _ = evals[0].call(tmp);
                        return info.len;
                    },
                    else => {
                        return evals[0].call(tmp).len;
                    },
                }
            }
        },
    };
}

pub fn mk_assign(ref: OpDef, op_: OpDef) OpDef {
    const dt_fn = comptime op_.dtype;
    return OpDef{
        .name = "assign",
        .ctx = ref.ctx,
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

pub fn mk_set(name: str, op_: OpDef) OpDef {
    const dt_fn = comptime op_.dtype;
    return OpDef{
        .name = "set",
        .ctx = op_.ctx,
        .inputs = &.{op_},
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
                Refl.set(&.{name}, tmp, evals[0].call(tmp));
            }
        },
    };
}

pub fn mk_simple(bc: *BuildContext, opname: str, ops_: []const ?OpDef, type_idx: ?usize, func: type) OpDef {
    comptime {
        var dt_fns: [ops_.len]?DTypeFn = undefined;
        for (ops_, 0..) |op_, i| {
            dt_fns[i] = if (op_) |op| op.dtype else null;
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
        const bdt_fn = b_.dtype;
        return OpDef{
            .name = "index",
            .ctx = a_.ctx,
            .inputs = &.{ a_, b_ },
            .dtype = struct {
                fn call(th: TypeHint) ?type {
                    var th_ = th;
                    th_.parent_t = usize;
                    _ = bdt_fn(th_);

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

pub fn mk_block(ops: []const ?OpDef) OpDef {
    const N = ops.len;
    return mk_simple(ops[0].?.ctx, "block", ops, N - 1, struct {
        inline fn call(
            ret_type: type,
            noalias tmp: anytype,
            evals: anytype,
        ) ret_type {
            inline for (0..N - 1) |i| {
                _ = evals[i].call(tmp);
            }
            return evals[N - 1].call(tmp);
        }
    });
}
