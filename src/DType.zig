pub const DType = enum(u8) {
    U1,
    U4,
    U8,
    U16,
    U32,
    U64,
    I4,
    I8,
    I16,
    I32,
    I64,
    F16,
    F32,
    F64,

    pub fn toType(comptime self: DType) type {
        return switch (self) {
            .U1 => u1,
            .U4 => u4,
            .U8 => u8,
            .U16 => u16,
            .U32 => u32,
            .U64 => u64,
            .I4 => i4,
            .I8 => i8,
            .I16 => i16,
            .I32 => i32,
            .I64 => i64,
            .F16 => f16,
            .F32 => f32,
            .F64 => f64,
        };
    }

    pub fn fromType(comptime T: type) DType {
        return switch (T) {
            u1 => .U1,
            u4 => .U4,
            u8 => .U8,
            u16 => .U16,
            u32 => .U32,
            u64 => .U64,
            i4 => .I4,
            i8 => .I8,
            i16 => .I16,
            i32 => .I32,
            i64 => .I64,
            f16 => .F16,
            f32 => .F32,
            f64 => .F64,
            else => @compileError("Unsupported type."),
        };
    }

    pub fn size(comptime self: DType) usize {
        return @sizeOf(self.toType());
    }

    pub fn bitSize(comptime self: DType) usize {
        return @bitSizeOf(self.toType());
    }
};
