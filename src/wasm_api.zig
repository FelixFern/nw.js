const std = @import("std");
const wasm_allocator = std.heap.wasm_allocator;

const NDArray = @import("core/ndarray.zig").NDArray;
const creation = @import("core/creation.zig");

export fn wasm_alloc(len: usize) usize {
    const slice = wasm_allocator.alloc(u8, len) catch return 0;
    return @intFromPtr(slice.ptr);
}

export fn wasm_free(ptr: usize, len: usize) void {
    const start: [*]u8 = @ptrFromInt(ptr);
    wasm_allocator.free(start[0..len]);
}

fn writeResult(arr: *NDArray, out_ptr: usize) void {
    const out: [*]usize = @ptrFromInt(out_ptr);
    out[0] = @intFromPtr(arr.data.ptr);
    out[1] = arr.data.len;

    wasm_allocator.free(arr.shape);
}

fn shapeSlice(shape_ptr: usize, shape_len: usize) []const usize {
    const start: [*]const usize = @ptrFromInt(shape_ptr);
    return start[0..shape_len];
}

export fn wasm_zeros(shape_ptr: usize, shape_len: usize, out_ptr: usize) i32 {
    const shape = shapeSlice(shape_ptr, shape_len);
    var arr = creation.zeros(wasm_allocator, shape) catch return -1;
    writeResult(&arr, out_ptr);
    return 0;
}

export fn wasm_ones(shape_ptr: usize, shape_len: usize, out_ptr: usize) i32 {
    const shape = shapeSlice(shape_ptr, shape_len);
    var arr = creation.ones(wasm_allocator, shape) catch return -1;
    writeResult(&arr, out_ptr);
    return 0;
}

export fn wasm_full(shape_ptr: usize, shape_len: usize, value: f64, out_ptr: usize) i32 {
    const shape = shapeSlice(shape_ptr, shape_len);
    var arr = creation.full(wasm_allocator, shape, value) catch return -1;
    writeResult(&arr, out_ptr);
    return 0;
}

export fn wasm_arange(start: f64, stop: f64, step: f64, out_ptr: usize) i32 {
    var arr = creation.arange(wasm_allocator, start, stop, step) catch return -1;
    writeResult(&arr, out_ptr);
    return 0;
}

export fn wasm_linspace(start: f64, stop: f64, count: usize, out_ptr: usize) i32 {
    var arr = creation.linspace(wasm_allocator, start, stop, count) catch return -1;
    writeResult(&arr, out_ptr);
    return 0;
}
