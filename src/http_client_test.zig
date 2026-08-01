const std = @import("std");
const client = @import("http_client.zig");

test "HttpClient initialization is deterministic" {
    const http_client = client.HttpClient.init(std.testing.allocator);
    try std.testing.expectEqual(@as(?u32, null), http_client.timeout_ms);
}

test "HttpClient timeout initialization preserves the configured value" {
    const http_client = client.HttpClient.initWithTimeout(std.testing.allocator, 250);
    try std.testing.expectEqual(@as(?u32, 250), http_client.timeout_ms);
}

test "GET remains the public HTTP method" {
    try std.testing.expectEqualStrings("GET", @tagName(client.HttpMethod.GET));
}

test "HttpClient returns ConnectionFailed on closed port" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var client = client.HttpClient.init(allocator);

    const result = client.get("127.0.0.1", "/", null);
    if (result) |_| {
        try std.testing.expect(false);
    } else |err| {
        try std.testing.expectEqual(client.HttpError.ConnectionFailed, err);
    }
}
