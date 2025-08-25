const std = @import("std");
const OpBuilder = @import("OpBuilder.zig").OpBuilder;

fn Vec(comptime T: type, bitlen: usize) type {
    return @Vector(bitlen / @bitSizeOf(T), T);
}

const El: type = Vec(f32, 512);

export fn adder_zig_native(
    noalias A: [*]const El,
    noalias B: [*]const El,
    noalias C: [*]El,
    len: usize,
    num: El,
) void {
    for (0..len) |i|
        C[i] = A[i] + B[i] + num;
}

export fn adder_zig(noalias inp: *const AddExpr.input_t) void {
    for (0..inp.A.len) |i|
        inp.C[i] = inp.A[i] + inp.B[i] + inp.num;
}

extern fn adder_custom_exported(*const anyopaque) void;

export fn sum_zig_native(
    noalias A: [*]const El,
    len: usize,
    out: *El,
) void {
    var acc = std.mem.zeroes(El);
    for (0..len) |i|
        acc = acc + A[i];
    out.* = acc;
}

export fn sum_zig(noalias inp: *const SumExpr.input_t) void {
    var acc = std.mem.zeroes(El);
    for (0..inp.A.len) |i|
        acc = acc + inp.A[i];
    inp.out.* = acc;
}

extern fn sum_custom_exported(*const anyopaque) void;

const SumExpr = blk: {
    var ob = OpBuilder.init();
    const i = ob.ref("i", usize, null);
    const A = ob.var_("A", true).index(i.val());
    const acc = ob.ref("acc", null, null);
    const loop = acc.assign(acc.val().add(A)).for_range(i, .{
        .stop = ob.var_("A", true).len(),
    }, false);
    const block = ob.block(&.{
        loop,
        ob.var_("out", true),
        acc.val().set("out"),
    });

    break :blk block.build().evaluator(struct {
        A: []const El,
        out: *El,
        len: usize,
    }).export_("sum_custom_exported", .c);
};

const AddExpr = blk: {
    var ob = OpBuilder.init();
    const i = ob.var_("i", false);
    const A = ob.var_("A", true).index(i);
    const B = ob.var_("B", true).index(i);
    const C = ob.ref("C", null, "inputs").index(i);
    const loop = C.assign(A.add(B).add(ob.var_(
        "num",
        true,
    ))).for_range(ob.ref("i", usize, null), .{
        .stop = ob.var_("A", true).len(),
    }, false);

    break :blk loop.build().evaluator(struct {
        A: []const El,
        B: []const El,
        C: []El,
        num: El,
    }).export_("adder_custom_exported", .c);
};

const SumNum = blk: {
    var ob = OpBuilder.init();
    const i = ob.var_("init", true);
    const loop = i.add(ob.const_(1).cast(null)).set("init").for_range(ob.const_("i"), .{
        .stop = ob.const_(50),
    }, true);

    break :blk ob.block(&.{ loop, ob.var_("i", false).cast(u32) }).build().evaluator(struct {
        init: *u32,
    }).export_("comptime_test", .c);
};

extern fn comptime_test(*const anyopaque) void;

fn bench_add() !void {
    const allocator = std.heap.page_allocator;
    const A = try allocator.alloc(El, 1024 * 1024);
    const B = try allocator.alloc(El, 1024 * 1024);
    const C = try allocator.alloc(El, 1024 * 1024);
    defer {
        allocator.free(A);
        allocator.free(B);
        allocator.free(C);
    }

    var inp: AddExpr.input_t = .{ .A = A, .B = B, .C = C, .num = @splat(1) };

    std.debug.print("Num f32 = {}\n", .{1024 * 1024 * @typeInfo(El).vector.len});
    const iters = 100;

    @memset(A, @splat(1));
    @memset(B, @splat(5));
    @memset(C, @splat(0));
    try benchmark("pure zig element wise add", adder_zig_native, .{
        A.ptr,
        B.ptr,
        C.ptr,
        B.len,
        @as(El, @splat(1)),
    }, iters);
    std.debug.print("result = {}\n", .{C[5][0]});

    @memset(A, @splat(1));
    @memset(B, @splat(5));
    @memset(C, @splat(0));
    try benchmark("zig element wise add", adder_zig, .{&inp}, iters);
    std.debug.print("result = {}\n", .{C[5][0]});

    @memset(A, @splat(1));
    @memset(B, @splat(5));
    @memset(C, @splat(0));
    try benchmark("custom element wise add", adder_custom_exported, .{&inp}, iters);
    std.debug.print("result = {}\n", .{C[5][0]});
}

fn bench_sum() !void {
    const allocator = std.heap.page_allocator;
    const A = try allocator.alloc(El, 1024 * 1024);
    defer {
        allocator.free(A);
    }

    var out: El = @splat(0);
    var inp: SumExpr.input_t = .{ .A = A, .out = &out };

    @memset(A, @splat(1));

    std.debug.print("Num f32 = {}\n", .{A.len * @typeInfo(El).vector.len});
    const iters = 100;

    out = @splat(0);
    try benchmark("pure zig reduce sum", sum_zig_native, .{
        A.ptr,
        A.len,
        &out,
    }, iters);
    std.debug.print("result = {}\n", .{@as(u64, @intFromFloat(@reduce(.Add, out)))});

    try benchmark("zig reduce sum", sum_zig, .{&inp}, iters);
    std.debug.print("result = {}\n", .{@as(u128, @intFromFloat(@reduce(.Add, out)))});

    out = @splat(0);
    try benchmark("custom reduce sum", sum_custom_exported, .{&inp}, iters);
    std.debug.print("result = {}\n", .{@as(u128, @intFromFloat(@reduce(.Add, out)))});
}

pub fn benchmark(
    name: []const u8,
    func: anytype,
    args: anytype,
    iters: usize,
) !void {
    var timer = std.time.Timer.start() catch unreachable;
    const allocator = std.heap.page_allocator;
    var times = try allocator.alloc(u64, iters);
    defer allocator.free(times);

    // warmup
    for (0..50) |_| @call(.auto, func, args);

    for (0..iters) |i| {
        timer.reset();
        @call(.auto, func, args);
        times[i] = timer.read();
    }

    var mean: f64 = 0;
    for (times) |t| mean += @floatFromInt(t);
    mean /= @floatFromInt(iters);

    var variance: f64 = 0;
    for (times) |t| {
        const diff = @as(f64, @floatFromInt(t)) - mean;
        variance += diff * diff;
    }
    variance /= @floatFromInt(iters);
    const stddev = @sqrt(variance);

    std.debug.print("{s}: mean={d:.3} ms, σ={d:.3} ms (iters={d})\n", .{
        name,
        mean / 1e6, // convert ns → ms
        stddev / 1e6,
        iters,
    });
}

pub fn main() !void {
    try bench_add();
    std.debug.print("\n", .{});
    try bench_sum();

    comptime var init: u32 = 5;
    _ = comptime SumNum.eval(&.{ .init = &init });
    std.debug.print("compt result = {}\n", .{init});
}
