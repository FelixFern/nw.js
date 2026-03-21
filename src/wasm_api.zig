const std = @import("std");
const wasm_allocator = std.heap.wasm_allocator;

export fn wasm_alloc(len: usize) usize {
    const slice = wasm_allocator.alloc(u8, len) catch return 0;
    return @intFromPtr(slice.ptr);
}

export fn wasm_free(ptr: usize, len: usize) void {
    const start: [*]u8 = @ptrFromInt(ptr);
    wasm_allocator.free(start[0..len]);
}

export fn add(a: i32, b: i32) i32 {
    return a + b;
}

export fn sum_f64(ptr: usize, len: usize) f64 {
    const start: [*]const f64 = @ptrFromInt(ptr);
    const slice = start[0..len];

    var total: f64 = 0.0;
    for (slice) |val| {
        total += val;
    }
    return total;
}
