pub const ConnPoolError = error {
    out_of_capacity,
    stream_not_found,
};

pub const QueueError = error {
    invalid_capacity,
    queue_empty,
    queue_full,
};