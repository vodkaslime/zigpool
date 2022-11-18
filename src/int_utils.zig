const std = @import("std");
const testing = std.testing;

// Parse action index from a u128 integer.
pub fn parseActionIndex(bi: u128) u64 {
    return @truncate(u64, bi >> 64);
}

// Parse actual u64 value from u128 integer.
pub fn parseValue(bi: u128) u64 {
    return @truncate(u64, bi);
}

// Assemble action index and value into a u128 big integer.
pub fn assembleBigInteger(action_index: u64, value: u64) u128 {
    return (@intCast(u128, action_index) << 64) | @intCast(u128, value);
}

test "test_behavior" {
    const action_index: u64 = 123;
    const value: u64 = 42;

    const bi = assembleBigInteger(action_index, value);

    try testing.expectEqual(action_index, parseActionIndex(bi));
    try testing.expectEqual(value, parseValue(bi));
}