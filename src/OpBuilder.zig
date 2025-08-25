const std = @import("std");
const eql = std.mem.eql;
const str = [:0]const u8;
const BuildContext = @import("BuildContext.zig").BuildContext;
const OpDef = @import("OpDef.zig").OpDef;
const OpImpl = @import("OpImpl.zig");
const Ops = @import("BasicOps.zig");

pub const OpBuilder = struct {
    ctx: *BuildContext,
    op: OpDef,

    fn opn(ob: ?OpBuilder) ?OpDef {
        return if (ob) |b| b.op else null;
    }

    pub fn build(self: OpBuilder) OpDef {
        return self.op;
    }

    pub fn init() OpBuilder {
        var ctx = BuildContext.init();
        return .{ .ctx = &ctx, .op = undefined };
    }

    pub fn custom(self: OpBuilder, op: OpDef) OpBuilder {
        op.ctx = self.ctx;
        return .{ .ctx = self.ctx, .op = op };
    }

    pub fn void_(self: OpBuilder, dtype: ?type) OpBuilder {
        return .{ .ctx = self.ctx, .op = OpImpl.mk_void(self.ctx, dtype) };
    }

    pub fn const_(self: OpBuilder, comptime v: anytype) OpBuilder {
        return .{ .ctx = self.ctx, .op = OpImpl.mk_const(self.ctx, v) };
    }

    pub fn var_(self: OpBuilder, comptime name: str, comptime is_input: bool) OpBuilder {
        return .{ .ctx = self.ctx, .op = OpImpl.mk_var(self.ctx, name, is_input) };
    }

    pub fn ref(self: OpBuilder, comptime name: str, dtype: ?type, scope_: ?str) OpBuilder {
        return .{ .ctx = self.ctx, .op = OpImpl.mk_ref(self.ctx, name, dtype, scope_) };
    }

    pub fn val(a: OpBuilder) OpBuilder {
        return .{ .ctx = a.ctx, .op = OpImpl.mk_val(a.op) };
    }

    pub fn cast(a: OpBuilder, dtype: ?type) OpBuilder {
        return .{ .ctx = a.ctx, .op = OpImpl.mk_cast(a.op, dtype) };
    }

    pub fn len(a: OpBuilder) OpBuilder {
        return .{ .ctx = a.ctx, .op = OpImpl.mk_len(a.op) };
    }

    pub fn assign(lhs: OpBuilder, rhs: OpBuilder) OpBuilder {
        return .{ .ctx = lhs.ctx, .op = OpImpl.mk_assign(lhs.op, rhs.op) };
    }

    pub fn set(rhs: OpBuilder, name: str) OpBuilder {
        return .{ .ctx = rhs.ctx, .op = OpImpl.mk_set(name, rhs.op) };
    }

    pub fn index(a: OpBuilder, b: OpBuilder) OpBuilder {
        return .{ .ctx = a.ctx, .op = OpImpl.mk_index(a.op, b.op) };
    }

    pub fn add(a: OpBuilder, b: OpBuilder) OpBuilder {
        return .{ .ctx = a.ctx, .op = Ops.mk_add(a.op, b.op) };
    }

    pub fn sub(a: OpBuilder, b: OpBuilder) OpBuilder {
        return .{ .ctx = a.ctx, .op = Ops.mk_sub(a.op, b.op) };
    }

    pub fn mul(a: OpBuilder, b: OpBuilder) OpBuilder {
        return .{ .ctx = a.ctx, .op = Ops.mk_mul(a.op, b.op) };
    }

    pub fn div(a: OpBuilder, b: OpBuilder) OpBuilder {
        return .{ .ctx = a.ctx, .op = Ops.mk_div(a.op, b.op) };
    }

    pub fn mod(a: OpBuilder, b: OpBuilder) OpBuilder {
        return .{ .ctx = a.ctx, .op = Ops.mk_mod(a.op, b.op) };
    }

    pub fn neg(a: OpBuilder) OpBuilder {
        return .{ .ctx = a.ctx, .op = Ops.mk_neg(a.op) };
    }

    pub fn eq(a: OpBuilder, b: OpBuilder) OpBuilder {
        return .{ .ctx = a.ctx, .op = Ops.mk_eq(a.op, b.op) };
    }

    pub fn neq(a: OpBuilder, b: OpBuilder) OpBuilder {
        return .{ .ctx = a.ctx, .op = Ops.mk_neq(a.op, b.op) };
    }

    pub fn not(a: OpBuilder) OpBuilder {
        return .{ .ctx = a.ctx, .op = Ops.mk_not(a.op) };
    }

    pub fn or_(a: OpBuilder, b: OpBuilder) OpBuilder {
        return .{ .ctx = a.ctx, .op = Ops.mk_or(a.op, b.op) };
    }

    pub fn and_(a: OpBuilder, b: OpBuilder) OpBuilder {
        return .{ .ctx = a.ctx, .op = Ops.mk_and(a.op, b.op) };
    }

    pub fn lt(a: OpBuilder, b: OpBuilder) OpBuilder {
        return .{ .ctx = a.ctx, .op = Ops.mk_lt(a.op, b.op) };
    }

    pub fn lte(a: OpBuilder, b: OpBuilder) OpBuilder {
        return .{ .ctx = a.ctx, .op = Ops.mk_lte(a.op, b.op) };
    }

    pub fn gt(a: OpBuilder, b: OpBuilder) OpBuilder {
        return .{ .ctx = a.ctx, .op = Ops.mk_gt(a.op, b.op) };
    }

    pub fn gte(a: OpBuilder, b: OpBuilder) OpBuilder {
        return .{ .ctx = a.ctx, .op = Ops.mk_gte(a.op, b.op) };
    }

    pub fn bitand(a: OpBuilder, b: OpBuilder) OpBuilder {
        return .{ .ctx = a.ctx, .op = Ops.mk_bitand(a.op, b.op) };
    }

    pub fn bitor(a: OpBuilder, b: OpBuilder) OpBuilder {
        return .{ .ctx = a.ctx, .op = Ops.mk_bitor(a.op, b.op) };
    }

    pub fn bitxor(a: OpBuilder, b: OpBuilder) OpBuilder {
        return .{ .ctx = a.ctx, .op = Ops.mk_bitxor(a.op, b.op) };
    }

    pub fn bitnot(a: OpBuilder) OpBuilder {
        return .{ .ctx = a.ctx, .op = Ops.mk_bitnot(a.op) };
    }

    pub fn block(self: OpBuilder, ops: []const ?OpBuilder) OpBuilder {
        comptime {
            var opdefs: [ops.len]?OpDef = undefined;
            for (ops, 0..) |op, i| opdefs[i] = opn(op);
            return .{ .ctx = self.ctx, .op = OpImpl.mk_block(&opdefs) };
        }
    }

    pub fn ifelse(cond: OpBuilder, then_body: ?OpBuilder, else_body: ?OpBuilder) OpBuilder {
        return .{ .ctx = cond.ctx, .op = Ops.mk_ifelse(cond.op, opn(then_body), opn(else_body)) };
    }

    pub fn for_(init_: ?OpBuilder, cond: OpBuilder, body: OpBuilder, comptime is_inline: bool) OpBuilder {
        return .{ .ctx = cond.ctx, .op = Ops.mk_for(
            opn(init_),
            cond,
            body,
            is_inline,
        ) };
    }

    pub fn for_range(
        body: OpBuilder,
        iref: OpBuilder,
        v: struct {
            stop: OpBuilder,
            start: ?OpBuilder = null,
            step: ?OpBuilder = null,
            cond: ?OpBuilder = null,
        },
        comptime is_inline: bool,
    ) OpBuilder {
        return .{ .ctx = body.ctx, .op = Ops.mk_for_range(iref.op, .{
            .start = opn(v.start),
            .stop = v.stop.op,
            .step = opn(v.step),
            .body = body.op,
            .cond = opn(v.cond),
        }, is_inline) };
    }
};
