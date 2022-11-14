const std = @import("std");
const net = std.net;
const Allocator = std.mem.Allocator;
const AutoHashMap = std.AutoHashMap;

const zigpool = @import("zigpool");

pub const io_mode = .evented;

const SimpleServer = struct {
    const Self = @This();

    allocator: Allocator,
    clients: AutoHashMap(
        *@Frame(Self.handleConn),
        net.StreamServer.Connection,
    ),

    pub fn init(allocator: Allocator) Self {
        var clients = std.AutoHashMap(
            *@Frame(Self.handleConn),
            net.StreamServer.Connection,
        ).init(allocator);
        return Self {
            .allocator = allocator,
            .clients = clients,
        };
    }

    pub fn listen(self: *Self, port: u16) !void {
        var listener = net.StreamServer.init(.{});
        try listener.listen(net.Address.initIp4(.{ 0,0,0,0 }, port));

        std.log.info("server starting to server on port: {}", .{ port });

        while (true) {
            const conn = listener.accept() catch |err| switch (err) {
                error.ProcessFdQuotaExceeded, error.SystemFdQuotaExceeded, error.SystemResources => continue,
                error.SocketNotListening => return,
                else => return err,
            };

            std.log.info("client connected from: {}", .{ conn.address });

            const frame = self.allocator.create(@Frame(Self.handleConn)) catch {
                conn.stream.close();
                continue;
            };

            self.clients.putNoClobber(frame, conn) catch {
                self.allocator.destroy(frame);
                conn.stream.close();
                continue;
            };

            frame.* = async self.handleConn(conn);
        }
    }

    fn handleConn(self: *Self, conn: net.StreamServer.Connection) !void {
        defer {
            conn.stream.close();
            suspend {
                _ = self.clients.remove(@frame());
            }
        }

        var buf: [1024]u8 = undefined;

        while (true) {
            const r = try conn.stream.read(&buf);
            if (r == 0) {
                return;
            }
            _ = try conn.stream.write(buf[0..r]);
        }
    }
};

pub fn main() !void {
    // Initialte allocator.
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var server = SimpleServer.init(allocator);
    var server_frame = async server.listen(9000);
    defer {
        await server_frame catch {};
    }

    std.time.sleep(100 * std.time.ns_per_ms);

    const cfg = zigpool.Config {
        .host = "127.0.0.1",
        .port = 9000,
        .capacity = 3,
    };
    var pool = try zigpool.ConnPool.init(allocator, cfg);
    
    var buf: [1024]u8 = undefined;
    
    var stream1 = try pool.getConn();
    try stream1.writer().writeAll("here we go 1");
    var n1 = try stream1.reader().read(&buf);
    std.log.info("the ack from server is: {s}", .{ buf[0..n1] });

    var stream2 = try pool.getConn();
    try stream2.writer().writeAll("here we go 2");
    var n2 = try stream2.reader().read(&buf);
    std.log.info("the ack from server is: {s}", .{ buf[0..n2] });

    var stream3 = try pool.getConn();
    try stream3.writer().writeAll("here we go 3");
    var n3 = try stream3.reader().read(&buf);
    std.log.info("the ack from server is: {s}", .{ buf[0..n3] });

    try pool.returnConn(stream1);
    try pool.returnConn(stream2);
    try pool.returnConn(stream3);

    stream1 = try pool.getConn();
    try stream1.writer().writeAll("here we go 1");
    n1 = try stream1.reader().read(&buf);
    std.log.info("the ack from server is: {s}", .{ buf[0..n1] });

    stream2 = try pool.getConn();
    try stream2.writer().writeAll("here we go 2");
    n2 = try stream2.reader().read(&buf);
    std.log.info("the ack from server is: {s}", .{ buf[0..n2] });

    stream3 = try pool.getConn();
    try stream3.writer().writeAll("here we go 3");
    n3 = try stream3.reader().read(&buf);
    std.log.info("the ack from server is: {s}", .{ buf[0..n3] });

    defer pool.deinit();
}