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