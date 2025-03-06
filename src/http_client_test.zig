const std = @import("std");
const testing = std.testing;
const HTTPClient = @import("http_client.zig").HTTPClient;

test "Basic GET request returns 200 OK" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    const allocator = gpa.allocator();

    var client = HTTPClient.init(allocator, "httpbin.org", 80);

    var response = try client.get("/get", null);
    defer response.deinit();

    try testing.expectEqual(@as(u16, 200), response.status_code);
    try testing.expect(response.body.len > 0);

    // Verify body contains JSON with expected fields
    try testing.expect(std.mem.indexOf(u8, response.body, "\"url\"") != null);

    const leaked = gpa.deinit();
    try testing.expect(leaked == .ok);
}

test "Custom headers are properly sent" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    const allocator = gpa.allocator();

    var client = HTTPClient.init(allocator, "httpbin.org", 80);

    // Define custom headers
    var headers = std.StringHashMap([]const u8).init(allocator);
    defer headers.deinit();
    try headers.put("X-Custom-Header", "CustomValue");
    try headers.put("User-Agent", "ZigHTTPClientTest");

    var response = try client.get("/get", headers);
    defer response.deinit();

    try testing.expectEqual(@as(u16, 200), response.status_code);

    // Verify our custom headers are echoed back in the response body
    try testing.expect(std.mem.indexOf(u8, response.body, "\"X-Custom-Header\": \"CustomValue\"") != null);
    try testing.expect(std.mem.indexOf(u8, response.body, "\"User-Agent\": \"ZigHTTPClientTest\"") != null);

    const leaked = gpa.deinit();
    try testing.expect(leaked == .ok);
}

test "JSON endpoint returns valid JSON" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    const allocator = gpa.allocator();

    var client = HTTPClient.init(allocator, "httpbin.org", 80);

    var response = try client.get("/json", null);
    defer response.deinit();

    try testing.expectEqual(@as(u16, 200), response.status_code);

    // Check if Content-Type header contains application/json
    const content_type = response.headers.get("Content-Type") orelse
        response.headers.get("content-type") orelse "";
    try testing.expect(std.mem.indexOf(u8, content_type, "application/json") != null);

    // Verify basic JSON structure
    try testing.expect(std.mem.indexOf(u8, response.body, "{") != null);
    try testing.expect(std.mem.indexOf(u8, response.body, "}") != null);

    const leaked = gpa.deinit();
    try testing.expect(leaked == .ok);
}

test "HTML endpoint returns HTML content" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    const allocator = gpa.allocator();

    var client = HTTPClient.init(allocator, "httpbin.org", 80);

    var response = try client.get("/html", null);
    defer response.deinit();

    try testing.expectEqual(@as(u16, 200), response.status_code);

    // Check if Content-Type header contains text/html
    const content_type = response.headers.get("Content-Type") orelse
        response.headers.get("content-type") orelse "";
    try testing.expect(std.mem.indexOf(u8, content_type, "text/html") != null);

    // Verify HTML structure
    try testing.expect(std.mem.indexOf(u8, response.body, "<html>") != null);
    try testing.expect(std.mem.indexOf(u8, response.body, "</html>") != null);

    const leaked = gpa.deinit();
    try testing.expect(leaked == .ok);
}

test "404 Not Found is handled correctly" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    const allocator = gpa.allocator();

    var client = HTTPClient.init(allocator, "httpbin.org", 80);

    var response = try client.get("/status/404", null);
    defer response.deinit();

    try testing.expectEqual(@as(u16, 404), response.status_code);

    const leaked = gpa.deinit();
    try testing.expect(leaked == .ok);
}

test "301 Redirect is handled correctly" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    const allocator = gpa.allocator();

    var client = HTTPClient.init(allocator, "httpbin.org", 80);

    var response = try client.get("/status/301", null);
    defer response.deinit();

    try testing.expectEqual(@as(u16, 301), response.status_code);

    // Check for Location header
    const location = response.headers.get("Location") orelse
        response.headers.get("location");
    try testing.expect(location != null);

    const leaked = gpa.deinit();
    try testing.expect(leaked == .ok);
}

test "Large response body is handled correctly" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    const allocator = gpa.allocator();

    var client = HTTPClient.init(allocator, "httpbin.org", 80);

    // Request a large response (5KB)
    var response = try client.get("/bytes/5120", null);
    defer response.deinit();

    try testing.expectEqual(@as(u16, 200), response.status_code);
    try testing.expectEqual(@as(usize, 5120), response.body.len);

    const leaked = gpa.deinit();
    try testing.expect(leaked == .ok);
}

test "Invalid hostname handling" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    const allocator = gpa.allocator();

    var client = HTTPClient.init(allocator, "nonexistentdomain123456789.org", 80);

    // This should return an error
    const result = client.get("/get", null);
    try testing.expectError(error.UnknownHostName, result);

    const leaked = gpa.deinit();
    try testing.expect(leaked == .ok);
}

test "Memory leaks in client" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    const allocator = gpa.allocator();

    // Create and use multiple clients and responses to check for leaks
    {
        var client = HTTPClient.init(allocator, "httpbin.org", 80);

        // Custom headers that need to be freed
        var headers = std.StringHashMap([]const u8).init(allocator);
        try headers.put("Test-Header-1", "Value1");
        try headers.put("Test-Header-2", "Value2");

        var response = try client.get("/get", headers);
        response.deinit();

        headers.deinit();
    }

    // GPA will detect any leaks when we call gpa.deinit()
    const leaked = gpa.deinit();
    try testing.expect(leaked == .ok);
}

test "Headers are correctly parsed" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    const allocator = gpa.allocator();

    var client = HTTPClient.init(allocator, "httpbin.org", 80);

    var response = try client.get("/response-headers?X-Test-Header=TestValue", null);
    defer response.deinit();

    try testing.expectEqual(@as(u16, 200), response.status_code);

    // Check for our custom response header
    const test_header = response.headers.get("X-Test-Header") orelse "";
    try testing.expectEqualStrings("TestValue", test_header);

    const leaked = gpa.deinit();
    try testing.expect(leaked == .ok);
}
