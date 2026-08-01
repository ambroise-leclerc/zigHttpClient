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

test "serializeRequest produces correct GET request bytes" {
    const allocator = std.testing.allocator;
    const result = try client.HttpClient.serializeRequest(allocator, .GET, "example.com", "/index.html", null);
    defer allocator.free(result);

    const expected = "GET /index.html HTTP/1.1\r\nHost: example.com\r\nConnection: close\r\n\r\n";
    try std.testing.expectEqualStrings(expected, result);
}

test "serializeRequest includes custom headers" {
    const allocator = std.testing.allocator;
    var headers = std.StringHashMap([]const u8).init(allocator);
    defer headers.deinit();
    try headers.put("User-Agent", "TestClient/1.0");
    try headers.put("Accept", "text/html");

    const result = try client.HttpClient.serializeRequest(allocator, .GET, "api.example.com", "/v1/data", headers);
    defer allocator.free(result);

    try std.testing.expect(std.mem.startsWith(u8, result, "GET /v1/data HTTP/1.1\r\n"));
    try std.testing.expect(std.mem.indexOf(u8, result, "Host: api.example.com\r\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "User-Agent: TestClient/1.0\r\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "Accept: text/html\r\n") != null);
    try std.testing.expect(std.mem.endsWith(u8, result, "\r\n\r\n"));
}
