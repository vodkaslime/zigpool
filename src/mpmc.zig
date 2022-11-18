const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const Mutex = std.Thread.Mutex;

const int_utils = @import("./int_utils.zig");

const err = @import("./err.zig");
const QueueError = err.QueueError;

// This is a lock_free mpmc queue design:
//
// A ring buffer with two pointers: head_index and tail_index.
// Actions of popItem() and getItem() move the pointers above
// via CAS actions.
//
// Basic item type is u64, and a valid item value cannot be 0,
// since 0 stands for empty.
//
// action_index guarantees the mpmc queue without ABA issue.
pub const Queue = struct {
    const Self = @This();

    allocator: Allocator,
    ring_buf: []u128,
    head_index: usize,
    tail_index: usize,
    wait_time: u64,

    // Initializes the mpmc queue with capacity and wait_time.
    pub fn init(allocator: Allocator, capacity: usize, wait_time: u64) !Self {
        if (capacity == 0) {
            return QueueError.invalid_capacity;
        }

        var ring_buf = try allocator.alloc(u128, capacity);
        for (ring_buf) |_, index| {
            ring_buf[index] = int_utils.assembleBigInteger(@intCast(u64, index), 0);
        }

        return Self {
            .allocator = allocator,
            .ring_buf = ring_buf,
            .head_index = 0,
            .tail_index = 0,
            .wait_time = wait_time,
        };
    }

    // Deinit the mpmc queue. Free self.ring_buf.
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.ring_buf);
    }

    // Wait self.wait_time for next run of action.
    fn wait(self: *Self) void {
        std.time.sleep(self.wait_time * std.time.ns_per_ms);
    }

    // Pop item from the queue.
    // If the queue is not empty, return the item.
    // It the queue is empty, return QueueError.queue_empty.
    pub fn popItem(self: *Self) !u64 {
        const capacity = self.ring_buf.len;

        while (true) {
            const head_index = self.head_index;
            const ptr = head_index % capacity;

            const expected_val = self.ring_buf[ptr];
            const action_index = int_utils.parseActionIndex(expected_val);
            const value = int_utils.parseValue(expected_val);

            // ABA issue happened.
            if (action_index > @intCast(u64, head_index + capacity)) {
                self.wait();
                continue;
            }

            // If the value is 0, then the queue is empty.
            // No need to move the pointer.
            if (value == 0) {
                return QueueError.queue_empty;
            }

            const new_val = int_utils.assembleBigInteger(@intCast(u64, head_index + capacity), 0);

            const res_option = @cmpxchgStrong(u128, &self.ring_buf[ptr], expected_val, new_val, .SeqCst, .SeqCst);
            if (res_option == null) {
                _ = @atomicRmw(u64, &self.head_index, .Add, 1, .SeqCst);
                return value;
            } else {
                self.wait();
                continue;
            }
        }
    }

    // Put item into the queue.
    // If the queue is not full, put the item.
    // It the queue is empty, return QueueError.queue_full.
    pub fn putItem(self: *Self, item: u64) !void {
        const capacity = self.ring_buf.len;

        while (true) {
            const tail_index = self.tail_index;
            const ptr = tail_index % capacity;

            const expected_val = self.ring_buf[ptr];
            const action_index = int_utils.parseActionIndex(expected_val);
            const value = int_utils.parseValue(expected_val);
            
            // ABA issue happened.
            if (action_index > @intCast(u64, tail_index)) {
                self.wait();
                continue;
            }

            // If the value is not null, then the queue is full.
            // No need to move the pointer.
            if (value != 0) {
                return QueueError.queue_full;
            }

            const new_val = int_utils.assembleBigInteger(@intCast(u64, tail_index + capacity), item);

            const res_option = @cmpxchgStrong(u128, &self.ring_buf[ptr], expected_val, new_val, .SeqCst, .SeqCst);
            if (res_option == null) {
                _ = @atomicRmw(u64, &self.tail_index, .Add, 1, .SeqCst);
                return;
            } else {
                self.wait();
                continue;
            }
        }
    }
};

test "queue_init_empty" {
    try testing.expectError(QueueError.invalid_capacity, Queue.init(testing.allocator, 0, 10));
}

test "basic_test" {
    var q = try Queue.init(testing.allocator, 3, 10);
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
    var q = try Queue.init(testing.allocator, 20, 10);
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