const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const NDArray = @import("ndarray.zig").NDArray;

pub fn zeros(allocator: Allocator, shape: []const usize) !NDArray {
    const arr = try NDArray.init(allocator, shape);
    @memset(arr.data, 0.0);
    return arr;
}

pub fn ones(allocator: Allocator, shape: []const usize) !NDArray {
    const arr = try NDArray.init(allocator, shape);
    @memset(arr.data, 1.0);
    return arr;
}

pub fn full(allocator: Allocator, shape: []const usize, value: f64) !NDArray {
    const arr = try NDArray.init(allocator, shape);
    @memset(arr.data, value);
    return arr;
}

pub fn arange(allocator: Allocator, start: f64, stop: f64, step: f64) !NDArray {
    const size: usize = @intFromFloat(@ceil((stop - start) / step));
    const arr = try NDArray.init(allocator, &[_]usize{size});

    for (arr.data, 0..) |*val, idx| {
        val.* = start + @as(f64, @floatFromInt(idx)) * step;
    }

    return arr;
}

pub fn linspace(allocator: Allocator, start: f64, stop: f64, count: usize) !NDArray {
    const arr = try NDArray.init(allocator, &[_]usize{count});

    if (count == 1) {
        arr.data[0] = start;
        return arr;
    }

    const s = (stop - start) / @as(f64, @floatFromInt(count - 1));
    for (arr.data, 0..) |*val, idx| {
        val.* = start + s * @as(f64, @floatFromInt(idx));
    }
    return arr;
}

test "zeros" {
    var arr = try zeros(testing.allocator, &[_]usize{ 2, 3 });
    defer arr.deinit();

    for (arr.data) |val| {
        try testing.expectEqual(@as(f64, 0.0), val);
    }
}

test "ones" {
    var arr = try ones(testing.allocator, &[_]usize{ 2, 3 });
    defer arr.deinit();

    for (arr.data) |val| {
        try testing.expectEqual(@as(f64, 1.0), val);
    }
}

test "full" {
    var arr = try full(testing.allocator, &[_]usize{ 2, 2 }, 7.5);
    defer arr.deinit();

    for (arr.data) |val| {
        try testing.expectEqual(@as(f64, 7.5), val);
    }
}

test "arange integer step" {
    var arr = try arange(testing.allocator, 0, 5, 1);
    defer arr.deinit();

    try testing.expectEqual(@as(usize, 5), arr.data.len);
    try testing.expectEqual(@as(f64, 0.0), arr.data[0]);
    try testing.expectEqual(@as(f64, 1.0), arr.data[1]);
    try testing.expectEqual(@as(f64, 4.0), arr.data[4]);
}

test "arange with step > 1" {
    var arr = try arange(testing.allocator, 1, 10, 3);
    defer arr.deinit();

    try testing.expectEqual(@as(usize, 3), arr.data.len);
    try testing.expectEqual(@as(f64, 1.0), arr.data[0]);
    try testing.expectEqual(@as(f64, 4.0), arr.data[1]);
    try testing.expectEqual(@as(f64, 7.0), arr.data[2]);
}

test "linspace" {
    var arr = try linspace(testing.allocator, 0, 1, 5);
    defer arr.deinit();

    try testing.expectEqual(@as(usize, 5), arr.data.len);
    try testing.expectApproxEqAbs(@as(f64, 0.0), arr.data[0], 1e-10);
    try testing.expectApproxEqAbs(@as(f64, 0.25), arr.data[1], 1e-10);
    try testing.expectApproxEqAbs(@as(f64, 0.5), arr.data[2], 1e-10);
    try testing.expectApproxEqAbs(@as(f64, 0.75), arr.data[3], 1e-10);
    try testing.expectApproxEqAbs(@as(f64, 1.0), arr.data[4], 1e-10);
}

test "linspace single point" {
    var arr = try linspace(testing.allocator, 5, 5, 1);
    defer arr.deinit();

    try testing.expectEqual(@as(usize, 1), arr.data.len);
    try testing.expectEqual(@as(f64, 5.0), arr.data[0]);
}
