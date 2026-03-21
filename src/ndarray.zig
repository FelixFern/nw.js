pub const DType = enum {
    f32,
    f64,
    i32,
    i64,
    u8,

    pub fn sizeOf(self: DType) usize {
        return switch (self) {
            .f32 => 4,
            .f64 => 8,
            .i32 => 4,
            .i64 => 8,
            .u8 => 1,
        };
    }
};
