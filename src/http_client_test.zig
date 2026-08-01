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

    const result = try client.HttpClient.serializeRequest(allocator, .GET, "api.example.com", "/v1/data", headers);
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


test "HttpClient defaults proxy to null" {
    const http_client = client.HttpClient.init(std.testing.allocator);
    try std.testing.expectEqual(null, http_client.proxy);
}

test "ProxyConfig initializes with default values" {
    const proxy = client.ProxyConfig{
        .host = "proxy.example.com",
        .port = 8080,
    };
    try std.testing.expectEqualStrings("proxy.example.com", proxy.host);
    try std.testing.expectEqual(@as(u16, 8080), proxy.port);
    try std.testing.expectEqual(null, proxy.username);
    try std.testing.expectEqual(null, proxy.password);
}

test "ProxyConfig initializes with all fields" {
    const proxy = client.ProxyConfig{
        .host = "secure-proxy.example.com",
        .port = 443,
        .username = "user",
        .password = "pass",
    };
    try std.testing.expectEqualStrings("secure-proxy.example.com", proxy.host);
    try std.testing.expectEqual(@as(u16, 443), proxy.port);
    try std.testing.expectEqualStrings("user", proxy.username.?);
    try std.testing.expectEqualStrings("pass", proxy.password.?);
}
