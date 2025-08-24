const std = @import("std");
const eql = std.mem.eql;
const str = [:0]const u8;
const BuildContext = @import("BuildContext.zig").BuildContext;
const OpDef = @import("OpDef.zig").OpDef;
const Ops = @import("OpImpl.zig");

pub const OpBuilder = struct {
    ctx: *BuildContext,
    op: OpDef,

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

    pub fn const_(self: OpBuilder, comptime v: anytype) OpBuilder {
        return .{ .ctx = self.ctx, .op = Ops.Ops.mk_const(self.ctx, v) };
    }

    pub fn var_(self: OpBuilder, comptime name: str, comptime is_input: bool) OpBuilder {
        return .{ .ctx = self.ctx, .op = Ops.mk_var(self.ctx, name, is_input) };
    }

    pub fn ref(self: OpBuilder, comptime name: str, dtype: ?type, scope_: ?str) OpBuilder {
        return .{ .ctx = self.ctx, .op = Ops.mk_ref(self.ctx, name, dtype, scope_) };
    }

    pub fn cast(a: OpBuilder, dtype: ?type) OpBuilder {
        return .{ .ctx = a.ctx, .op = Ops.mk_cast(a.op, dtype) };
    }

    pub fn assign(lhs: OpBuilder, rhs: OpBuilder) OpBuilder {
        if (!(eql(u8, lhs.op.name, "ref") or eql(u8, lhs.op.name, "index"))) @compileError("Expected ref");
        return .{ .ctx = lhs.ctx, .op = Ops.mk_assign(lhs.op, rhs.op) };
    }

    pub fn index(a: OpBuilder, b: OpBuilder) OpBuilder {
        return .{ .ctx = a.ctx, .op = Ops.mk_index(a.op, b.op) };
    }

    pub fn add(a: OpBuilder, b: OpBuilder) OpBuilder {
        return .{ .ctx = a.ctx, .op = Ops.mk_add(a.op, b.op) };
    }

    pub fn loop_range(
        body: OpBuilder,
        iname: str,
        v: struct {
            stop: OpBuilder,
            start: ?OpBuilder = null,
            step: ?OpBuilder = null,
        },
        scope: ?str,
    ) OpBuilder {
        return .{ .ctx = body.ctx, .op = Ops.mk_loop_range(iname, .{
            .start = if (v.start) |s| s.op else null,
            .stop = v.stop.op,
            .step = if (v.step) |s| s.op else null,
            .body = body.op,
        }, scope) };
    }
};
