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

test "Reject CR in host" {
    var http_client = client.HttpClient.init(std.testing.allocator);
    const result = (&http_client).sendRequest(.GET, "host\r\nInjected: true", "/path", null);
    try std.testing.expectError(client.HttpError.RequestSplittingAttempt, result);
}

test "Reject LF in host" {
    var http_client = client.HttpClient.init(std.testing.allocator);
    const result = (&http_client).sendRequest(.GET, "host\nInjected: true", "/path", null);
    try std.testing.expectError(client.HttpError.RequestSplittingAttempt, result);
}

test "Reject CR in path" {
    var http_client = client.HttpClient.init(std.testing.allocator);
    const result = (&http_client).sendRequest(.GET, "host", "/path\r\nInjected: true", null);
    try std.testing.expectError(client.HttpError.RequestSplittingAttempt, result);
}

test "Reject LF in path" {
    var http_client = client.HttpClient.init(std.testing.allocator);
    const result = (&http_client).sendRequest(.GET, "host", "/path\nInjected: true", null);
    try std.testing.expectError(client.HttpError.RequestSplittingAttempt, result);
}

test "Reject CR in header name" {
    var http_client = client.HttpClient.init(std.testing.allocator);
    var headers = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer headers.deinit();
    try headers.put("Header\r\nInjected: true", "value");
    const result = (&http_client).sendRequest(.GET, "host", "/path", headers);
    try std.testing.expectError(client.HttpError.RequestSplittingAttempt, result);
}

test "Reject LF in header name" {
    var http_client = client.HttpClient.init(std.testing.allocator);
    var headers = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer headers.deinit();
    try headers.put("Header\nInjected: true", "value");
    const result = (&http_client).sendRequest(.GET, "host", "/path", headers);
    try std.testing.expectError(client.HttpError.RequestSplittingAttempt, result);
}

test "Reject CR in header value" {
    var http_client = client.HttpClient.init(std.testing.allocator);
    var headers = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer headers.deinit();
    try headers.put("Header", "value\r\nInjected: true");
    const result = (&http_client).sendRequest(.GET, "host", "/path", headers);
    try std.testing.expectError(client.HttpError.RequestSplittingAttempt, result);
}

test "Reject LF in header value" {
    var http_client = client.HttpClient.init(std.testing.allocator);
    var headers = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer headers.deinit();
    try headers.put("Header", "value\nInjected: true");
    const result = (&http_client).sendRequest(.GET, "host", "/path", headers);
    try std.testing.expectError(client.HttpError.RequestSplittingAttempt, result);
}
