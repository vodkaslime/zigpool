# zigpool

## What is zigpool
A simple and lite tcp connection pool, based on lock_free mpmc queue implemented in Zig language.

## Usage
- Import zigpool package as dependency.
- Set up config with zigpool.Config:
```
const cfg = zigpool.Config {
    .host = "127.0.0.1",
    .port = 9000,
    .capacity = 3,
};
```
- Set up the actual connection pool with the config:
```
var pool = try zigpool.ConnPool.init(allocator, cfg);
```
- Get a connection from the connection pool:
```
var stream = try pool.getConn();
```
- Return it back to connection pool:
```
try pool.returnConn(stream);
```
- So far zigpool does not have async daemon to automatically monitor connection activities, therefore if a connection is closed, it's user's responsibility to call `dropConn` to make zigpool destroy and drop it.
```
try pool.dropConn(stream);
```

For more detailed use cases, check out examples.