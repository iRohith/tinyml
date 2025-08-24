const std = @import("std");
const str = [:0]const u8;
const OpDef = @import("OpDef.zig").OpDef;
const mk_simple = @import("OpImpl.zig").mk_simple;
const ops = @import("OpImpl.zig");

pub fn mk_add(a_: OpDef, b_: OpDef) OpDef {
    return mk_simple(a_.ctx, "add", &.{ a_, b_ }, null, struct {
        pub inline fn call(
            ret_type: type,
            noalias tmp: anytype,
            evals: anytype,
        ) ret_type {
            return evals[0].call(tmp) + evals[1].call(tmp);
        }
    });
}

pub fn mk_sub(a_: OpDef, b_: OpDef) OpDef {
    return mk_simple(a_.ctx, "sub", &.{ a_, b_ }, null, struct {
        pub inline fn call(
            ret_type: type,
            noalias tmp: anytype,
            evals: anytype,
        ) ret_type {
            return evals[0].call(tmp) - evals[1].call(tmp);
        }
    });
}

pub fn mk_mul(a_: OpDef, b_: OpDef) OpDef {
    return mk_simple(a_.ctx, "mul", &.{ a_, b_ }, null, struct {
        pub inline fn call(
            ret_type: type,
            noalias tmp: anytype,
            evals: anytype,
        ) ret_type {
            return evals[0].call(tmp) * evals[1].call(tmp);
        }
    });
}

pub fn mk_div(a_: OpDef, b_: OpDef) OpDef {
    return mk_simple(a_.ctx, "div", &.{ a_, b_ }, null, struct {
        pub inline fn call(
            ret_type: type,
            noalias tmp: anytype,
            evals: anytype,
        ) ret_type {
            const a = evals[0].call(tmp);
            const b = evals[1].call(tmp);
            switch (@typeInfo(ret_type)) {
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
}

pub fn mk_mod(a_: OpDef, b_: OpDef) OpDef {
    return mk_simple(a_.ctx, "mod", &.{ a_, b_ }, null, struct {
        pub inline fn call(
            ret_type: type,
            noalias tmp: anytype,
            evals: anytype,
        ) ret_type {
            return evals[0].call(tmp) % evals[1].call(tmp);
        }
    });
}

pub fn mk_neg(a_: OpDef) OpDef {
    return mk_simple(a_.ctx, "neg", &.{a_}, null, struct {
        pub inline fn call(
            ret_type: type,
            noalias tmp: anytype,
            evals: anytype,
        ) ret_type {
            return -evals[0].call(tmp);
        }
    });
}

// compare

pub fn mk_eq(a_: OpDef, b_: OpDef) OpDef {
    return mk_simple(a_.ctx, "eq", &.{ a_, b_, ops.mk_void(a_.ctx, bool) }, 2, struct {
        pub inline fn call(
            ret_type: type,
            noalias tmp: anytype,
            evals: anytype,
        ) ret_type {
            return std.meta.eql(evals[0].call(tmp), evals[1].call(tmp));
        }
    });
}

pub fn mk_neq(a_: OpDef, b_: OpDef) OpDef {
    return mk_simple(a_.ctx, "neq", &.{ a_, b_, ops.mk_void(a_.ctx, bool) }, 2, struct {
        pub inline fn call(
            ret_type: type,
            noalias tmp: anytype,
            evals: anytype,
        ) ret_type {
            return !std.meta.eql(evals[0].call(tmp), evals[1].call(tmp));
        }
    });
}

pub fn mk_not(a_: OpDef) OpDef {
    return mk_simple(a_.ctx, "not", &.{ a_, ops.mk_void(a_.ctx, bool) }, 1, struct {
        pub inline fn call(
            ret_type: type,
            noalias tmp: anytype,
            evals: anytype,
        ) ret_type {
            return !evals[0].call(tmp);
        }
    });
}

pub fn mk_or(a_: OpDef, b_: OpDef) OpDef {
    return mk_simple(a_.ctx, "or", &.{ a_, b_, ops.mk_void(a_.ctx, bool) }, 2, struct {
        pub inline fn call(
            ret_type: type,
            noalias tmp: anytype,
            evals: anytype,
        ) ret_type {
            return evals[0].call(tmp) or evals[1].call(tmp);
        }
    });
}

pub fn mk_and(a_: OpDef, b_: OpDef) OpDef {
    return mk_simple(a_.ctx, "and", &.{ a_, b_, ops.mk_void(a_.ctx, bool) }, 2, struct {
        pub inline fn call(
            ret_type: type,
            noalias tmp: anytype,
            evals: anytype,
        ) ret_type {
            return evals[0].call(tmp) and evals[1].call(tmp);
        }
    });
}

pub fn mk_lt(a_: OpDef, b_: OpDef) OpDef {
    return mk_simple(a_.ctx, "lt", &.{ a_, b_, ops.mk_void(a_.ctx, bool) }, 2, struct {
        pub inline fn call(
            ret_type: type,
            noalias tmp: anytype,
            evals: anytype,
        ) ret_type {
            return evals[0].call(tmp) < evals[1].call(tmp);
        }
    });
}

pub fn mk_lte(a_: OpDef, b_: OpDef) OpDef {
    return mk_simple(a_.ctx, "lte", &.{ a_, b_, ops.mk_void(a_.ctx, bool) }, 2, struct {
        pub inline fn call(
            ret_type: type,
            noalias tmp: anytype,
            evals: anytype,
        ) ret_type {
            return evals[0].call(tmp) <= evals[1].call(tmp);
        }
    });
}

pub fn mk_gt(a_: OpDef, b_: OpDef) OpDef {
    return mk_simple(a_.ctx, "gt", &.{ a_, b_, ops.mk_void(a_.ctx, bool) }, 2, struct {
        pub inline fn call(
            ret_type: type,
            noalias tmp: anytype,
            evals: anytype,
        ) ret_type {
            return evals[0].call(tmp) > evals[1].call(tmp);
        }
    });
}

pub fn mk_gte(a_: OpDef, b_: OpDef) OpDef {
    return mk_simple(a_.ctx, "gte", &.{ a_, b_, ops.mk_void(a_.ctx, bool) }, 2, struct {
        pub inline fn call(
            ret_type: type,
            noalias tmp: anytype,
            evals: anytype,
        ) ret_type {
            return evals[0].call(tmp) >= evals[1].call(tmp);
        }
    });
}

// bitwise

pub fn mk_bitand(a_: OpDef, b_: OpDef) OpDef {
    return mk_simple(a_.ctx, "bitand", &.{ a_, b_ }, null, struct {
        pub inline fn call(
            ret_type: type,
            noalias tmp: anytype,
            evals: anytype,
        ) ret_type {
            return evals[0].call(tmp) & evals[1].call(tmp);
        }
    });
}

pub fn mk_bitor(a_: OpDef, b_: OpDef) OpDef {
    return mk_simple(a_.ctx, "bitor", &.{ a_, b_ }, null, struct {
        pub inline fn call(
            ret_type: type,
            noalias tmp: anytype,
            evals: anytype,
        ) ret_type {
            return evals[0].call(tmp) | evals[1].call(tmp);
        }
    });
}

pub fn mk_bitxor(a_: OpDef, b_: OpDef) OpDef {
    return mk_simple(a_.ctx, "bitxor", &.{ a_, b_ }, null, struct {
        pub inline fn call(
            ret_type: type,
            noalias tmp: anytype,
            evals: anytype,
        ) ret_type {
            return evals[0].call(tmp) ^ evals[1].call(tmp);
        }
    });
}

pub fn mk_bitnot(a_: OpDef) OpDef {
    return mk_simple(a_.ctx, "bitnot", &.{a_}, null, struct {
        pub inline fn call(
            ret_type: type,
            noalias tmp: anytype,
            evals: anytype,
        ) ret_type {
            return ~evals[0].call(tmp);
        }
    });
}

pub fn mk_ifelse(cond: OpDef, then_body: ?OpDef, else_body: ?OpDef) OpDef {
    const has_then = then_body != null;
    const has_else = else_body != null;
    return mk_simple(cond.ctx, "ifelse", &.{ then_body, else_body, cond }, null, struct {
        pub inline fn call(
            ret_type: type,
            noalias tmp: anytype,
            evals: anytype,
        ) ret_type {
            if (evals[2].call(tmp)) {
                if (has_then) return evals[0].call(tmp);
            } else {
                if (has_else) return evals[1].call(tmp);
            }
            return undefined;
        }
    });
}

pub fn mk_for(
    init: ?OpDef,
    cond: OpDef,
    body: OpDef,
) OpDef {
    return mk_simple(body.ctx, "for_range", &.{
        init orelse ops.mk_void(body.ctx, void),
        cond,
        body,
    }, 2, struct {
        pub inline fn call(
            ret_type: type,
            noalias tmp: anytype,
            evals: anytype,
        ) ret_type {
            _ = evals[0].call(tmp);

            var ret: ret_type = undefined;
            while (evals[1].call(tmp)) {
                ret = evals[2].call(tmp);
            }

            return ret;
        }
    });
}

pub fn mk_for_range(
    comptime iname: str,
    v: struct {
        start: ?OpDef = null,
        stop: OpDef,
        step: ?OpDef = null,
        body: OpDef,
        cond: ?OpDef = null,
    },
) OpDef {
    const has_cond = v.cond != null;
    return mk_simple(v.body.ctx, "for_range", &.{
        ops.mk_ref(v.body.ctx, iname, usize, null),
        v.start orelse ops.mk_const(v.body.ctx, 0),
        v.stop,
        v.step orelse ops.mk_const(v.body.ctx, 1),
        v.body,
        v.cond,
    }, 4, struct {
        pub inline fn call(
            ret_type: type,
            noalias tmp: anytype,
            evals: anytype,
        ) ret_type {
            const i = evals[0].call(tmp);
            const step = evals[3].call(tmp);
            const stop = evals[2].call(tmp);

            i.* = evals[1].call(tmp);
            var ret: ret_type = undefined;

            if (comptime has_cond) {
                while (i.* < stop and evals[5].call(tmp)) {
                    ret = evals[4].call(tmp);
                    i.* += step;
                }
            } else {
                while (i.* < stop) {
                    ret = evals[4].call(tmp);
                    i.* += step;
                }
            }

            return ret;
        }
    });
}
