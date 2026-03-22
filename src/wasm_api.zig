const std = @import("std");
const wasm_allocator = std.heap.wasm_allocator;

const NDArray = @import("ndarray.zig").NDArray;

// -------------------------------------------------------
// Low-level memory helpers (Phase 1)
// -------------------------------------------------------

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

    // Free the shape — JS already knows it, and the NDArray struct
    // itself is on the stack (about to disappear). We only keep data alive.
    wasm_allocator.free(arr.shape);
}

fn shapeSlice(shape_ptr: usize, shape_len: usize) []const usize {
    const start: [*]const usize = @ptrFromInt(shape_ptr);
    return start[0..shape_len];
}

/// zeros(shape) — all elements 0.0
export fn wasm_zeros(shape_ptr: usize, shape_len: usize, out_ptr: usize) i32 {
    const shape = shapeSlice(shape_ptr, shape_len);
    var arr = NDArray.zeros(wasm_allocator, shape) catch return -1;
    writeResult(&arr, out_ptr);
    return 0;
}

/// ones(shape) — all elements 1.0
export fn wasm_ones(shape_ptr: usize, shape_len: usize, out_ptr: usize) i32 {
    const shape = shapeSlice(shape_ptr, shape_len);
    var arr = NDArray.ones(wasm_allocator, shape) catch return -1;
    writeResult(&arr, out_ptr);
    return 0;
}

/// full(shape, value) — all elements set to value
export fn wasm_full(shape_ptr: usize, shape_len: usize, value: f64, out_ptr: usize) i32 {
    const shape = shapeSlice(shape_ptr, shape_len);
    var arr = NDArray.full(wasm_allocator, shape, value) catch return -1;
    writeResult(&arr, out_ptr);
    return 0;
}

/// arange(start, stop, step) — 1D array [start, start+step, ...]
/// JS doesn't know the output length ahead of time, reads it from out[1].
export fn wasm_arange(start: f64, stop: f64, step: f64, out_ptr: usize) i32 {
    var arr = NDArray.arange(wasm_allocator, start, stop, step) catch return -1;
    writeResult(&arr, out_ptr);
    return 0;
}

/// linspace(start, stop, count) — 1D array of count evenly spaced values
export fn wasm_linspace(start: f64, stop: f64, count: usize, out_ptr: usize) i32 {
    var arr = NDArray.linspace(wasm_allocator, start, stop, count) catch return -1;
    writeResult(&arr, out_ptr);
    return 0;
}
