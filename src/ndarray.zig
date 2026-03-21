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
