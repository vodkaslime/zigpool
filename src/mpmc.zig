const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const Mutex = std.Thread.Mutex;

const err = @import("./err.zig");
const QueueError = err.QueueError;

// This is a lock_free mpmc queue design:
//
// A ring buffer with two pointers: head_index and tail_index.
// Actions of popItem() and getItem() move the pointers above
// via CAS actions.
//
// action_index guarantees the mpmc queue without ABA issue.
pub fn Queue(comptime T: type) type {

    const Node = struct {
        data: ?T,
        action_index: usize,
    };

    return struct {
        const Self = @This();

        allocator: Allocator,
        ring_buf: []*Node,
        head_index: usize,
        tail_index: usize,
        wait_time: u64,

        // Initializes the mpmc queue with capacity and wait_time.
        pub fn init(allocator: Allocator, capacity: usize, wait_time: u64) !Self {
            if (capacity == 0) {
                return QueueError.invalid_capacity;
            }

            var ring_buf = try allocator.alloc(*Node, capacity);
            for (ring_buf) |*item, index| {
                var node = try allocator.create(Node);
                node.* = Node {
                    .data = null,
                    .action_index = index,
                };
                item.* = node;
            }

            return Self {
                .allocator = allocator,
                .ring_buf = ring_buf,
                .head_index = 0,
                .tail_index = 0,
                .wait_time = wait_time,
            };
        }

        // Deinit the mpmc queue. Free the contents in self.ring_buf.
        pub fn deinit(self: *Self) void {
            for (self.ring_buf) |item| {
                self.allocator.destroy(item);
            }
            self.allocator.free(self.ring_buf);
        }

        // Wait self.wait_time for next run of action.
        fn wait(self: *Self) void {
            std.time.sleep(self.wait_time * std.time.ns_per_ms);
        }

        // Pop item from the queue.
        // If the queue is not empty, return the item.
        // It the queue is emptry, return QueueError.queue_empty.
        pub fn popItem(self: *Self) !T {
            const capacity = self.ring_buf.len;

            while (true) {
                const head_index = self.head_index;
                const ptr = head_index % capacity;

                const expected_node = self.ring_buf[ptr];
                
                // ABA issue happened.
                if (expected_node.action_index > head_index + capacity) {
                    self.wait();
                    continue;
                }

                // If the data is null, then the queue is empty.
                // No need to move the pointer.
                if (expected_node.data == null) {
                    return QueueError.queue_empty;
                }

                var new_node = try self.allocator.create(Node);
                new_node.* = Node {
                    .data = null,
                    .action_index = head_index + capacity,
                };

                const res_option = @cmpxchgStrong(*Node, &self.ring_buf[ptr], expected_node, new_node, .SeqCst, .SeqCst);
                if (res_option == null) {
                    _ = @atomicRmw(u64, &self.head_index, .Add, 1, .SeqCst);
                    var res = expected_node.data.?;
                    self.allocator.destroy(expected_node);
                    return res;
                } else {
                    self.allocator.destroy(new_node);
                    self.wait();
                    continue;
                }
            }
        }

        // Put item into the queue.
        // If the queue is not full, put the item.
        // It the queue is emptry, return QueueError.queue_full.
        pub fn putItem(self: *Self, item: T) !void {
            const capacity = self.ring_buf.len;

            while (true) {
                const tail_index = self.tail_index;
                const ptr = tail_index % capacity;

                var expected_node = self.ring_buf[ptr];
                
                // ABA issue happened.
                if (expected_node.action_index > tail_index) {
                    self.wait();
                    continue;
                }

                // If the data is not null, then the queue is full.
                // No need to move the pointer.
                if (expected_node.data != null) {
                    return QueueError.queue_full;
                }

                var new_node = try self.allocator.create(Node);
                new_node.* = Node {
                    .data = item,
                    .action_index = tail_index + capacity,
                };

                const res_option = @cmpxchgStrong(*Node, &self.ring_buf[ptr], expected_node, new_node, .SeqCst, .SeqCst);
                if (res_option == null) {
                    _ = @atomicRmw(u64, &self.tail_index, .Add, 1, .SeqCst);
                    self.allocator.destroy(expected_node);
                    return;
                } else {
                    self.allocator.destroy(new_node);
                    self.wait();
                    continue;
                }
            }
        }
    };
}

test "queue_init_empty" {
    try testing.expectError(QueueError.invalid_capacity, Queue(u8).init(testing.allocator, 0, 10));
}

test "basic_test" {
    var q = try Queue(u8).init(testing.allocator, 3, 10);
    defer q.deinit();

    try q.putItem(1);

    try q.putItem(2);

    try q.putItem(3);

    try testing.expectError(QueueError.queue_full, q.putItem(4));

    try testing.expectError(QueueError.queue_full, q.putItem(5));

    const a1 = try q.popItem();
    try testing.expectEqual(a1, 1);

    const a2 = try q.popItem();
    try testing.expectEqual(a2, 2);

    const a3 = try q.popItem();
    try testing.expectEqual(a3, 3);

    try testing.expectError(QueueError.queue_empty, q.popItem());

    try testing.expectError(QueueError.queue_empty, q.popItem());
}

test "test_multiple_actions" {
    var q = try Queue(u8).init(testing.allocator, 20, 10);
    defer q.deinit();

    var index: usize = 0;
    while (index < 1000): (index += 1) {
        try q.putItem(1);

        try q.putItem(2);

        try q.putItem(3);

        try q.putItem(4);

        try q.putItem(5);

        try q.putItem(6);

        const a1 = try q.popItem();
        try testing.expectEqual(a1, 1);

        const a2 = try q.popItem();
        try testing.expectEqual(a2, 2);

        const a3 = try q.popItem();
        try testing.expectEqual(a3, 3);

        const a4 = try q.popItem();
        try testing.expectEqual(a4, 4);

        const a5 = try q.popItem();
        try testing.expectEqual(a5, 5);

        const a6 = try q.popItem();
        try testing.expectEqual(a6, 6);
    }
}