const std = @import("std");
const OpBuilder = @import("OpBuilder.zig").OpBuilder;

export fn adder_zig(noalias inp: *const ExprEval.input_t) void {
    for (0..@as(usize, @intFromFloat(inp.len))) |i| inp.C[i] = inp.A[i] + inp.B[i] + @as(f32, @floatFromInt(inp.num));
}

extern fn adder_custom_exported(*const anyopaque) void;

const ExprEval = blk: {
    var ob = OpBuilder.init();
    const i = ob.var_("i", false);
    const A = ob.var_("A", true).index(i);
    const B = ob.var_("B", true).index(i);
    const C = ob.ref("C", null, "inputs").index(i);
    const loop = C.assign(A.add(B).add(ob.var_(
        "num",
        true,
    ).cast(null).cast(null).cast(null))).for_range("i", .{
        .stop = ob.var_("len", true).cast(null).cast(usize),
    });

    break :blk loop.build().evaluator(struct {
        A: [*]const f32,
        B: [*]const f32,
        C: [*]f32,
        num: i64,
        len: f32,
    }, .c);
};

comptime {
    @export(&ExprEval.ceval, .{ .name = "adder_custom_exported" });
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const A = try allocator.alloc(f32, 1024 * 1024);
    const B = try allocator.alloc(f32, 1024 * 1024);
    const C = try allocator.alloc(f32, 1024 * 1024);
    defer {
        allocator.free(A);
        allocator.free(B);
        allocator.free(C);
    }

    var inp: ExprEval.input_t = .{ .A = A.ptr, .B = B.ptr, .C = C.ptr, .len = @floatFromInt(C.len), .num = 5 };

    @memset(A, 1);
    @memset(B, 6);
    @memset(C, 0);

    adder_zig(&inp);
    std.log.debug("{}", .{C[100]});

    @memset(A, 1);
    @memset(B, 5);
    @memset(C, 0);

    adder_custom_exported(&inp);
    std.log.debug("{}", .{C[100]});

    // std.log.debug("{s}", .{
    //     @typeInfo(@FieldType(ExprEval._input_t, "loops")).@"struct".fields[0].name,
    // });
}
