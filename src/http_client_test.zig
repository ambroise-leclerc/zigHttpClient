const std = @import("std");
const testing = std.testing;
const client = @import("http_client.zig");
const HttpClient = client.HttpClient;

test "HttpClient - GET request to httpbin.org/get" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var http_client = HttpClient.init(allocator);

    // Create headers
    var headers = std.StringHashMap([]const u8).init(allocator);
    try headers.put("User-Agent", "Zig-Test-Client/0.1");

    // Make request
    const response = try http_client.get("httpbin.org", "/get", headers);
    defer response.deinit();

    // Verify status code
    try testing.expectEqual(@as(u16, 200), response.status_code);

    // Verify body contains expected data
    try testing.expect(std.mem.indexOf(u8, response.body, "\"url\": \"http://httpbin.org/get\"") != null);

    // Verify headers were sent properly
    try testing.expect(std.mem.indexOf(u8, response.body, "\"User-Agent\": \"Zig-Test-Client/0.1\"") != null);
}

test "HttpClient - GET request to httpbin.org/json" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var http_client = HttpClient.init(allocator);

    // Make request without custom headers
    const response = try http_client.get("httpbin.org", "/json", null);
    defer response.deinit();

    // Verify status code
    try testing.expectEqual(@as(u16, 200), response.status_code);

    // Verify body contains JSON data
    try testing.expect(std.mem.indexOf(u8, response.body, "\"slideshow\"") != null);
}

test "HttpClient - Error handling (non-existent path)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var http_client = HttpClient.init(allocator);

    // Make request to a path that should return 404
    const response = try http_client.get("httpbin.org", "/status/404", null);
    defer response.deinit();

    // Verify status code
    try testing.expectEqual(@as(u16, 404), response.status_code);
}
