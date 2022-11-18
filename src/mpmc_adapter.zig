const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const err = @import("./err.zig");
const mpmc = @import("./mpmc.zig");
const Queue = mpmc.Queue;
const QueueError = err.QueueError;

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

const SomeStruct = struct {
    a: u16,
    b: u64,
};

test "basic_test" {
    var adapter = try Adapter(SomeStruct).init(testing.allocator, 3, 10);
    defer adapter.deinit();

    const struct_1 = try testing.allocator.create(SomeStruct);
    defer testing.allocator.destroy(struct_1);

    struct_1.* = .{
        .a = 1,
        .b = 11,
    };

    const struct_2 = try testing.allocator.create(SomeStruct);
    defer testing.allocator.destroy(struct_2);

    struct_2.* = .{
        .a = 2,
        .b = 12,
    };

    const struct_3 = try testing.allocator.create(SomeStruct);
    defer testing.allocator.destroy(struct_3);

    struct_3.* = .{
        .a = 3,
        .b = 13,
    };

    const struct_4 = try testing.allocator.create(SomeStruct);
    defer testing.allocator.destroy(struct_4);

    struct_4.* = .{
        .a = 4,
        .b = 14,
    };

    const struct_5 = try testing.allocator.create(SomeStruct);
    defer testing.allocator.destroy(struct_5);

    struct_5.* = .{
        .a = 5,
        .b = 15,
    };

    try adapter.putItem(struct_1);
    try adapter.putItem(struct_2);
    try adapter.putItem(struct_3);
    try testing.expectError(QueueError.queue_full, adapter.putItem(struct_4));
    try testing.expectError(QueueError.queue_full, adapter.putItem(struct_5));

    const struct_get_1 = try adapter.popItem();
    try testing.expectEqual(struct_get_1.*, SomeStruct {
        .a = 1,
        .b = 11,
    });

    const struct_get_2 = try adapter.popItem();
    try testing.expectEqual(struct_get_2.*, SomeStruct {
        .a = 2,
        .b = 12,
    });

    const struct_get_3 = try adapter.popItem();
    try testing.expectEqual(struct_get_3.*, SomeStruct {
        .a = 3,
        .b = 13,
    });

    try testing.expectError(QueueError.queue_empty, adapter.popItem());

    try testing.expectError(QueueError.queue_empty, adapter.popItem());
}

test "test_multiple_actions" {
    var adapter = try Adapter(SomeStruct).init(testing.allocator, 20, 10);
    defer adapter.deinit();

    const struct_1 = try testing.allocator.create(SomeStruct);
    defer testing.allocator.destroy(struct_1);
    struct_1.* = .{
        .a = 1,
        .b = 11,
    };

    const struct_2 = try testing.allocator.create(SomeStruct);
    defer testing.allocator.destroy(struct_2);

    struct_2.* = .{
        .a = 2,
        .b = 12,
    };

    const struct_3 = try testing.allocator.create(SomeStruct);
    defer testing.allocator.destroy(struct_3);

    struct_3.* = .{
        .a = 3,
        .b = 13,
    };

    const struct_4 = try testing.allocator.create(SomeStruct);
    defer testing.allocator.destroy(struct_4);

    struct_4.* = .{
        .a = 4,
        .b = 14,
    };

    const struct_5 = try testing.allocator.create(SomeStruct);
    defer testing.allocator.destroy(struct_5);

    struct_5.* = .{
        .a = 5,
        .b = 15,
    };

    const struct_6 = try testing.allocator.create(SomeStruct);
    defer testing.allocator.destroy(struct_6);

    struct_6.* = .{
        .a = 6,
        .b = 16,
    };

    var index: usize = 0;
    while (index < 1000): (index += 1) {
        try adapter.putItem(struct_1);
        try adapter.putItem(struct_2);
        try adapter.putItem(struct_3);
        try adapter.putItem(struct_4);
        try adapter.putItem(struct_5);
        try adapter.putItem(struct_6);

        const struct_get_1 = try adapter.popItem();
        try testing.expectEqual(struct_get_1.*, SomeStruct {
            .a = 1,
            .b = 11,
        });

        const struct_get_2 = try adapter.popItem();
        try testing.expectEqual(struct_get_2.*, SomeStruct {
            .a = 2,
            .b = 12,
        });

        const struct_get_3 = try adapter.popItem();
        try testing.expectEqual(struct_get_3.*, SomeStruct {
            .a = 3,
            .b = 13,
        });

        const struct_get_4 = try adapter.popItem();
        try testing.expectEqual(struct_get_4.*, SomeStruct {
            .a = 4,
            .b = 14,
        });

        const struct_get_5 = try adapter.popItem();
        try testing.expectEqual(struct_get_5.*, SomeStruct {
            .a = 5,
            .b = 15,
        });

        const struct_get_6 = try adapter.popItem();
        try testing.expectEqual(struct_get_6.*, SomeStruct {
            .a = 6,
            .b = 16,
        });
    }
}