const std = @import("std");
const Allocator = std.mem.Allocator;

const mpmc = @import("./mpmc.zig");
const Queue = mpmc.Queue;

pub fn Adapter(comptime T: type) type {
    return struct {
        const Self = @This();

        queue: Queue,

        pub fn init(allocator: Allocator, capacity: usize, wait_time: u64) !Self {
            const queue = try Queue.init(allocator, capacity, wait_time);
            return Self {
                .queue = queue,
            };
        }

        pub fn deinit(self: *Self) void {
            self.queue.deinit();
        }

        pub fn popItem(self: *Self) !*T {
            const int_val = try self.queue.popItem();
            return @intToPtr(*T, @intCast(usize, int_val));
        }

        pub fn putItem(self: *Self, item: *const T) !void {
            const int_val = @intCast(u64, @ptrToInt(item));
            return self.queue.putItem(int_val);
        }
    };
}