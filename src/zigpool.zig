const std = @import("std");
const net = std.net;
const Allocator = std.mem.Allocator;
const AutoHashMap = std.AutoHashMap;
const Mutex = std.Thread.Mutex;
const Stream = net.Stream;

const err = @import("./err.zig");
const mpmc = @import("./mpmc.zig");
const ConnPoolError = err.ConnPoolError;
const QueueError = err.QueueError;

pub const Config = struct {
    host: []const u8,
    port: u16,
    capacity: usize,
};

const ConnStatus = enum {
    idle,
    borrowed,
};

pub const ConnPool = struct {
    const Self = @This();

    allocator: Allocator,
    config: Config,
    mutex: Mutex,
    queue: mpmc.Queue(*Stream),
    conns_map: AutoHashMap(*Stream, ConnStatus),

    pub fn init(allocator: Allocator, config: Config) !Self {
        var queue = try mpmc.Queue(*Stream).init(allocator, config.capacity, 10);
        var conns_map = AutoHashMap(*Stream, ConnStatus).init(allocator);
        return Self {
            .allocator = allocator,
            .config = config,
            .mutex = .{},
            .queue = queue,
            .conns_map = conns_map,
        };
    }

    pub fn deinit(self: *Self) void {
        self.queue.deinit();

        var iter = self.conns_map.iterator();
        while (iter.next()) |entry| {
            var stream = entry.key_ptr.*;
            stream.close();
            self.allocator.destroy(stream);
        }
    }

    fn createConn(self: *Self) !*Stream {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.conns_map.count() >= self.config.capacity) {
            return ConnPoolError.out_of_capacity;
        }

        var stream_ptr = try self.allocator.create(Stream);
        errdefer self.allocator.destroy(stream_ptr);
        
        const stream = try net.tcpConnectToHost(
            self.allocator,
            self.config.host,
            self.config.port
        );
        errdefer stream.close();
    
        stream_ptr.* = stream;

        try self.conns_map.putNoClobber(stream_ptr, .borrowed);
        
        return stream_ptr;
    }

    // Try getting a connection from mpmc queue. If cannot get one from queue,
    // try creating one.
    pub fn getConn(self: *Self) !*Stream {
        var stream = (self.queue.popItem()) catch |e| {
            if (e == QueueError.queue_empty) {
                return self.createConn();
            }
            return e;
        };

        var status_ptr_option = self.conns_map.getPtr(stream);
        if (status_ptr_option) |status_ptr| {
            status_ptr.* = .borrowed;
        } else {
            return ConnPoolError.stream_not_found;
        }
        return stream;
    }

    pub fn returnConn(self: *Self, stream: *Stream) !void {
        var status_ptr_option = self.conns_map.getPtr(stream);
        if (status_ptr_option) |status_ptr| {
            try self.queue.putItem(stream);
            status_ptr.* = .idle;
        } else {
            return ConnPoolError.stream_not_found;
        }
    } 

    // Notify the connection pool that the borrowed connection was already dropped.
    pub fn dropConn(self: *Self, stream: *Stream) !void {
        if (self.conns_map.remove(stream)) {
            stream.close();
            self.allocator.destroy(stream);
        } else {
            ConnPoolError.stream_not_found;
        }
    }
};