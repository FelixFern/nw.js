const std = @import("std");
const Allocator = std.mem.Allocator;

pub const NDArray = struct {
    data: []f64,
    shape: []usize,
    ndim: usize,
    allocator: Allocator,

    pub fn init(allocator: Allocator, shape: []const usize) !NDArray {
        var total: usize = 1;
        for (shape) |s| total *= s;

        const data = try allocator.alloc(f64, total);
        const owned_shape = try allocator.dupe(usize, shape);

        return NDArray{
            .data = data,
            .shape = owned_shape,
            .ndim = shape.len,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *NDArray) void {
        self.allocator.free(self.data);
        self.allocator.free(self.shape);
    }

    pub fn getItem(self: *const NDArray, indices: []const usize) f64 {
        const flat_index = self.flatIndex(indices);
        return self.data[flat_index];
    }

    pub fn setItem(self: *NDArray, indices: []const usize, value: f64) void {
        const flat_index = self.flatIndex(indices);
        self.data[flat_index] = value;
    }

    fn flatIndex(self: *const NDArray, indices: []const usize) usize {
        var flat_index: usize = 0;
        var multiplier: usize = 1;
        var i: usize = self.ndim;

        while (i > 0) {
            i -= 1;
            flat_index += indices[i] * multiplier;
            multiplier *= self.shape[i];
        }

        return flat_index;
    }
};

const testing = std.testing;

test "init allocates correct size" {
    var arr = try NDArray.init(testing.allocator, &[_]usize{ 3, 4 });
    defer arr.deinit();

    try testing.expectEqual(@as(usize, 12), arr.data.len);
    try testing.expectEqual(@as(usize, 2), arr.ndim);
    try testing.expectEqual(@as(usize, 3), arr.shape[0]);
    try testing.expectEqual(@as(usize, 4), arr.shape[1]);
}

test "init 1D array" {
    var arr = try NDArray.init(testing.allocator, &[_]usize{5});
    defer arr.deinit();

    try testing.expectEqual(@as(usize, 5), arr.data.len);
    try testing.expectEqual(@as(usize, 1), arr.ndim);
}

test "init 3D array" {
    var arr = try NDArray.init(testing.allocator, &[_]usize{ 2, 3, 4 });
    defer arr.deinit();

    try testing.expectEqual(@as(usize, 24), arr.data.len);
    try testing.expectEqual(@as(usize, 3), arr.ndim);
}

test "setItem and getItem 2D" {
    var arr = try NDArray.init(testing.allocator, &[_]usize{ 3, 4 });
    defer arr.deinit();

    arr.setItem(&[_]usize{ 0, 0 }, 1.0);
    arr.setItem(&[_]usize{ 1, 2 }, 42.0);
    arr.setItem(&[_]usize{ 2, 3 }, 99.5);

    try testing.expectEqual(@as(f64, 1.0), arr.getItem(&[_]usize{ 0, 0 }));
    try testing.expectEqual(@as(f64, 42.0), arr.getItem(&[_]usize{ 1, 2 }));
    try testing.expectEqual(@as(f64, 99.5), arr.getItem(&[_]usize{ 2, 3 }));
}

test "setItem and getItem 1D" {
    var arr = try NDArray.init(testing.allocator, &[_]usize{5});
    defer arr.deinit();

    arr.setItem(&[_]usize{3}, 7.7);
    try testing.expectEqual(@as(f64, 7.7), arr.getItem(&[_]usize{3}));
}

test "setItem and getItem 3D" {
    var arr = try NDArray.init(testing.allocator, &[_]usize{ 2, 3, 4 });
    defer arr.deinit();

    arr.setItem(&[_]usize{ 1, 2, 3 }, 123.0);
    try testing.expectEqual(@as(f64, 123.0), arr.getItem(&[_]usize{ 1, 2, 3 }));
}

test "flatIndex correctness" {
    var arr = try NDArray.init(testing.allocator, &[_]usize{ 3, 4 });
    defer arr.deinit();

    try testing.expectEqual(@as(usize, 0), arr.flatIndex(&[_]usize{ 0, 0 }));
    try testing.expectEqual(@as(usize, 3), arr.flatIndex(&[_]usize{ 0, 3 }));
    try testing.expectEqual(@as(usize, 4), arr.flatIndex(&[_]usize{ 1, 0 }));
    try testing.expectEqual(@as(usize, 11), arr.flatIndex(&[_]usize{ 2, 3 }));
}

test "shape is independent copy" {
    var shape = [_]usize{ 3, 4 };
    var arr = try NDArray.init(testing.allocator, &shape);
    defer arr.deinit();

    shape[0] = 999;
    try testing.expectEqual(@as(usize, 3), arr.shape[0]);
}
