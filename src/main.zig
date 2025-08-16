const std = @import("std");
const Op = @import("Ops.zig").Op;
const DType = @import("DType.zig").DType;

extern fn exported_eval(*const anyopaque) f32;

pub fn main() !void {
    const a = Op.variable("a");
    const b = Op.variable("b").cast();
    const c = Op.constant(2);

    const op = a.add(b);
    const op1 = op.div(b);
    const opc = op1.index(c.castTo(u32));

    var av: @Vector(4, f32) = .{ 1, 2, 3, 4 };
    av *= @splat(2);

    const ans = op1.eval(.{ .a = av, .b = @as(f32, 3.2) });
    std.log.debug("{}", .{ans});

    const ans1 = opc.eval(.{ .a = av, .b = @as(f32, 3.2) });
    std.log.debug("{}", .{ans1});

    const eval_t = a.add(b).cExport("exported_eval", @TypeOf(.{ .a = @as(f32, 1), .b = @as(f32, 1) }));
    const data: eval_t.input_type = .{ .a = 3, .b = 2 };
    std.log.debug("{}, {}", .{ eval_t.eval(&data), exported_eval(&data) });
}
