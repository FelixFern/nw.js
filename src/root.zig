const std = @import("std");

pub const NDArray = @import("core/ndarray.zig").NDArray;
pub const creation = @import("core/creation.zig");

test {
    std.testing.refAllDecls(@This());
}
