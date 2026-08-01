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
