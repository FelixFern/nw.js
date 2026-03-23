const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const NDArray = @import("ndarray.zig").NDArray;

pub fn reshape(allocator: Allocator, arr: *const NDArray, new_shape: []const usize) !NDArray {
    var new_total: usize = 1;
    for (new_shape) |size| {
        new_total *= size;
    }

    if (new_total != arr.data.len) return error.ShapeMismatch;

    const res = try NDArray.init(allocator, new_shape);
    @memcpy(res.data, arr.data);

    return res;
}

pub fn transpose(allocator: Allocator, arr: *const NDArray) !NDArray {
    if (arr.ndim != 2) return error.MismatchDimension;

    const rows = arr.shape[0];
    const cols = arr.shape[1];
    const res = try NDArray.init(allocator, &[_]usize{ cols, rows });

    for (0..cols) |c| {
        for (0..rows) |r| {
            res.setItem(&[_]usize{ c, r }, arr.getItem(&[_]usize{ r, c }));
        }
    }

    return res;
}

pub fn flatten(allocator: Allocator, arr: *const NDArray) !NDArray {
    return reshape(allocator, arr, &[_]usize{arr.data.len});
}
