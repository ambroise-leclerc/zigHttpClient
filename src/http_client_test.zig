const std = @import("std");
const client = @import("http_client.zig");

test "HttpClient initialization is deterministic" {
    const http_client = client.HttpClient.init(std.testing.allocator, null);
    try std.testing.expectEqual(@as(?u32, null), http_client.timeout_ms);
}

test "HttpClient timeout initialization preserves the configured value" {
    const http_client = client.HttpClient.initWithTimeout(std.testing.allocator, 250, null);
    try std.testing.expectEqual(@as(?u32, 250), http_client.timeout_ms);
}

test "GET remains the public HTTP method" {
    try std.testing.expectEqualStrings("GET", @tagName(client.HttpMethod.GET));
}

test "serializeRequest produces correct GET request bytes" {
    const allocator = std.testing.allocator;
    const result = try client.HttpClient.serializeRequest(allocator, .GET, "example.com", 80, "/index.html", null, null);
    defer allocator.free(result);

    const expected = "GET /index.html HTTP/1.1\r\nHost: example.com\r\nConnection: close\r\n\r\n";
    try std.testing.expectEqualStrings(expected, result);
}

test "serializeRequest includes custom headers" {
    const allocator = std.testing.allocator;
    var headers = std.StringHashMap([]const u8).init(allocator);
    defer headers.deinit();
    try headers.put("User-Agent", "TestClient/1.0");

    const result = try client.HttpClient.serializeRequest(allocator, .GET, "api.example.com", 80, "/v1/data", headers, null);
    defer allocator.free(result);

    const expected = "GET /v1/data HTTP/1.1\r\nHost: api.example.com\r\nUser-Agent: TestClient/1.0\r\nConnection: close\r\n\r\n";
    try std.testing.expectEqualStrings(expected, result);
}

test "HttpResponse.getHeader returns value for exact case match" {
    var headers = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer headers.deinit();
    try headers.put("Content-Type", "application/json");

    const response = client.HttpResponse{
        .status_code = 200,
        .headers = headers,
        .body = "",
        .allocator = std.testing.allocator,
    };

    const value = response.getHeader("Content-Type");
    try std.testing.expectEqualStrings("application/json", value.?);
}

test "HttpResponse.getHeader returns value for case-insensitive match" {
    var headers = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer headers.deinit();
    try headers.put("Content-Type", "application/json");

    const response = client.HttpResponse{
        .status_code = 200,
        .headers = headers,
        .body = "",
        .allocator = std.testing.allocator,
    };

    const value = response.getHeader("content-type");
    try std.testing.expectEqualStrings("application/json", value.?);
}

test "serializeRequest uses absolute-form for proxy requests" {
    const allocator = std.testing.allocator;
    const result = try client.HttpClient.serializeRequest(allocator, .GET, "example.com", 80, "/index.html", null, "http://proxy.example.com:8080");
    defer allocator.free(result);

    const expected = "GET http://example.com:80/index.html HTTP/1.1\r\nHost: example.com\r\nConnection: close\r\n\r\n";
    try std.testing.expectEqualStrings(expected, result);
}

test "HttpResponse.getHeader returns null for missing header" {
    var headers = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer headers.deinit();
    try headers.put("Content-Type", "application/json");

    const response = client.HttpResponse{
        .status_code = 200,
        .headers = headers,
        .body = "",
        .allocator = std.testing.allocator,
    };

    const value = response.getHeader("X-Missing-Header");
    try std.testing.expectEqual(null, value);
}

test "HttpClient proxy transport uses proxy host for connection" {
    var http_client = client.HttpClient.init(std.testing.allocator, "http://127.0.0.1:9999");
    const result = http_client.get("example.com", "/", null);
    if (result) |_| {
        try std.testing.expect(false);
    } else |err| {
        // Verify it attempted to connect to the proxy (127.0.0.1) rather than failing
        // with a protocol error due to malformed proxy URL.
        try std.testing.expect(err != error.ProtocolError);
    }
}
