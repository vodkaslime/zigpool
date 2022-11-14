const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const Mutex = std.Thread.Mutex;

const err = @import("./err.zig");
const QueueError = err.QueueError;

// This is a minimal mpmc queue design:
//
// Two locks each for producer side and consumer side,
// so that the mpmc is reduced to spsc styled ring buffer.
// Would consider using some lock_free/wait_free design in the future
// to improve performance.
pub fn Queue(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: Allocator,
        ring_buf: []T,
        producer_mutex: Mutex,
        consumer_mutex: Mutex,
        len: usize,
        head_index: usize,
        tail_index: usize,

        pub fn init(allocator: Allocator, capacity: usize) !Self {
            if (capacity == 0) {
                return QueueError.invalid_capacity;
            }

            var ring_buf = try allocator.alloc(T, capacity);
            return Self {
                .allocator = allocator,
                .ring_buf = ring_buf,
                .producer_mutex = .{},
                .consumer_mutex = .{},
                .len = 0,
                .head_index = 0,
                .tail_index = 0,
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.ring_buf);
        }

        pub fn getItem(self: *Self) !T {
            self.consumer_mutex.lock();
            defer self.consumer_mutex.unlock();
            
            if (self.len == 0) {
                return QueueError.queue_empty;
            }

            var res = self.ring_buf[self.head_index];

            return res;
        }

        pub fn popItem(self: *Self) !T {
            self.consumer_mutex.lock();
            defer self.consumer_mutex.unlock();
            
            if (self.len == 0) {
                return QueueError.queue_empty;
            }

            var res = self.ring_buf[self.head_index];

            self.head_index = (self.head_index + 1) % self.ring_buf.len;
            self.len -= 1;

            return res;
        }

        pub fn putItem(self: *Self, item: T) !void {
            self.producer_mutex.lock();
            defer self.producer_mutex.unlock();

            if (self.len == self.ring_buf.len) {
                return QueueError.queue_full;
            }

            self.ring_buf[self.tail_index] = item;

            self.tail_index = (self.tail_index + 1) % self.ring_buf.len;
            self.len += 1;
        }

        pub fn resize(self: *Self, new_capacity: usize) !void {
            if (new_capacity == 0) {
                return QueueError.invalid_capacity;
            }

            if (new_capacity == self.ring_buf.len) {
                return;
            }

            self.consumer_mutex.lock();
            defer self.consumer_mutex.unlock();

            self.producer_mutex.lock();
            defer self.producer_mutex.unlock();

            if (new_capacity < self.len) {
                return QueueError.resize_too_small;
            }

            var new_buf = try self.allocator.alloc(T, new_capacity);
            const old_buf = self.ring_buf;
            var index: usize = 0;
            while (index < self.len):(index += 1) {
                new_buf[index] = old_buf[(self.head_index + index) % old_buf.len];
            }

            self.ring_buf = new_buf;
            self.head_index = 0;
            self.tail_index = self.len % new_capacity;
            self.allocator.free(old_buf);
        }
    };
}

test "queue_init_empty" {
    try testing.expectError(QueueError.invalid_capacity, Queue(u8).init(testing.allocator, 0));
}

test "basic_test" {
    var q = try Queue(u8).init(testing.allocator, 3);
    defer q.deinit();
    try testing.expectEqual(q.len, 0);

    try q.putItem(1);
    try testing.expectEqual(q.len, 1);

    try q.putItem(2);
    try testing.expectEqual(q.len, 2);

    try q.putItem(3);
    try testing.expectEqual(q.len, 3);

    try testing.expectError(QueueError.queue_full, q.putItem(4));
    try testing.expectEqual(q.len, 3);

    try testing.expectError(QueueError.queue_full, q.putItem(5));
    try testing.expectEqual(q.len, 3);

    const a1 = try q.popItem();
    try testing.expectEqual(a1, 1);
    try testing.expectEqual(q.len, 2);

    const a2 = try q.popItem();
    try testing.expectEqual(a2, 2);
    try testing.expectEqual(q.len, 1);

    const a3 = try q.popItem();
    try testing.expectEqual(a3, 3);
    try testing.expectEqual(q.len, 0);

    try testing.expectError(QueueError.queue_empty, q.popItem());
    try testing.expectEqual(q.len, 0);

    try testing.expectError(QueueError.queue_empty, q.popItem());
    try testing.expectEqual(q.len, 0);
}

test "test_resize" {
    var q = try Queue(u8).init(testing.allocator, 5);
    defer q.deinit();
    try testing.expectEqual(q.len, 0);

    try q.putItem(1);
    try testing.expectEqual(q.len, 1);

    try q.putItem(2);
    try testing.expectEqual(q.len, 2);

    try q.putItem(3);
    try testing.expectEqual(q.len, 3);

    try q.putItem(4);
    try testing.expectEqual(q.len, 4);

    try q.putItem(5);
    try testing.expectEqual(q.len, 5);

    try testing.expectError(QueueError.resize_too_small, q.resize(3));

    const a1 = try q.popItem();
    try testing.expectEqual(a1, 1);
    try testing.expectEqual(q.len, 4);

    const a2 = try q.popItem();
    try testing.expectEqual(a2, 2);
    try testing.expectEqual(q.len, 3);

    const a3 = try q.popItem();
    try testing.expectEqual(a3, 3);
    try testing.expectEqual(q.len, 2);

    try q.resize(10);

    const a4 = try q.popItem();
    try testing.expectEqual(a4, 4);
    try testing.expectEqual(q.len, 1);

    const a5 = try q.popItem();
    try testing.expectEqual(a5, 5);
    try testing.expectEqual(q.len, 0);
}