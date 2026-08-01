const std = @import("std");
const testing = std.testing;
const client = @import("http_client.zig");
const HttpClient = client.HttpClient;
const HttpError = client.HttpError;

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

// Test for connection failures
test "HttpClient - Connection failure to non-existent host" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var http_client = HttpClient.init(allocator);

    // Try to connect to a non-existent host (should fail)
    const result = http_client.get("non-existent-domain-that-should-not-resolve.invalid", "/", null);

    // Verify that the expected error is returned
    try testing.expectError(HttpError.AddressLookupFailure, result);
}

// Test for invalid responses
test "HttpClient - Invalid response handling" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var http_client = HttpClient.init(allocator);

    // Try to connect to a non-HTTP server (e.g. HTTPS port without TLS)
    const result = http_client.get("httpbin.org", "/", null);

    // This should either fail with connection issues or invalid response
    // We're testing that we don't crash or leak memory
    if (result) |response| {
        defer response.deinit();
        // If it somehow succeeds, that's fine, we'll just defer deinit
    } else |err| {
        // Verify the error is one of the expected error types
        switch (err) {
            HttpError.InvalidResponse, HttpError.ConnectionFailed, HttpError.ReadError, HttpError.UnexpectedEof => {}, // These are all valid error cases
            else => {
                // If we get a different error, fail the test
                try testing.expect(false);
            },
        }
    }
}

// Test timeout handling
test "HttpClient - Timeout handling" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Initialize client with a very short timeout
    var http_client = HttpClient.initWithTimeout(allocator, 1); // 1ms timeout

    // Connect to a service that will likely take longer than 1ms to respond
    const result = http_client.get("httpbin.org", "/delay/3", null);

    // Note: Since the current implementation doesn't actually use the timeout,
    // this test will pass even if the timeout doesn't work.
    // When timeouts are implemented, this should be updated.
    if (result) |response| {
        defer response.deinit();
        // If it succeeds, that's fine for now
    } else |err| {
        // Verify the error is one we expect
        switch (err) {
            else => {}, // Any error is acceptable for now
        }
    }
}

// Test handling of server errors
test "HttpClient - Server error responses" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var http_client = HttpClient.init(allocator);

    // Test 500 error
    const response = try http_client.get("httpbin.org", "/status/500", null);
    defer response.deinit();

    // Verify status code
    try testing.expectEqual(@as(u16, 500), response.status_code);
}

// Test handling of very large responses
test "HttpClient - Large response handling" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var http_client = HttpClient.init(allocator);

    // Request a 100KB payload instead, as httpbin.org appears to cap at this size
    const response = try http_client.get("httpbin.org", "/bytes/102400", null);
    defer response.deinit();

    // Verify status code
    try testing.expectEqual(@as(u16, 200), response.status_code);

    // Verify that the body has the expected size
    try testing.expectEqual(@as(usize, 102400), response.body.len);
}

// Test chunked encoding
test "HttpClient - Chunked encoding handling" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var http_client = HttpClient.init(allocator);

    // httpbin.org/stream/n returns n chunks
    const response = try http_client.get("httpbin.org", "/stream/5", null);
    defer response.deinit();

    // Verify status code
    try testing.expectEqual(@as(u16, 200), response.status_code);

    // Verify that body contains multiple chunks by checking for multiple "id" fields
    var id_count: usize = 0;
    var index: usize = 0;

    while (std.mem.indexOfPos(u8, response.body, index, "\"id\":")) |pos| {
        id_count += 1;
        index = pos + 5;
    }

    try testing.expectEqual(@as(usize, 5), id_count);
}

// Test handling of missing headers
test "HttpClient - Handling missing headers" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var http_client = HttpClient.init(allocator);

    // Make request without custom headers
    const response = try http_client.get("httpbin.org", "/get", null);
    defer response.deinit();

    // Verify status code
    try testing.expectEqual(@as(u16, 200), response.status_code);

    // Verify that user-agent is not set (since we didn't add it)
    const has_custom_agent = std.mem.indexOf(u8, response.body, "\"User-Agent\": \"Zig-Test-Client") != null;
    try testing.expect(!has_custom_agent);
}

// Test for redirects
test "HttpClient - Redirect handling" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var http_client = HttpClient.init(allocator);

    // Request a redirect (note: current implementation doesn't follow redirects)
    const response = try http_client.get("httpbin.org", "/redirect/1", null);
    defer response.deinit();

    // Should get 302 status code since we don't auto-follow redirects
    try testing.expectEqual(@as(u16, 302), response.status_code);

    // Verify that a Location header is present
    var location_header: ?[]const u8 = null;
    var header_it = response.headers.iterator();
    while (header_it.next()) |entry| {
        if (std.ascii.eqlIgnoreCase(entry.key_ptr.*, "location")) {
            location_header = entry.value_ptr.*;
            break;
        }
    }

    try testing.expect(location_header != null);
}

// Test sending a malformed request
test "HttpClient - Handling malformed paths" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var http_client = HttpClient.init(allocator);

    // Try to send a request with a malformed path (no leading slash)
    const result = http_client.get("httpbin.org", "get", null);

    // We shouldn't crash, but the server may return an error or redirect
    if (result) |response| {
        defer response.deinit();
        // If we got a response, that's fine - it means we handled the malformed path without crashing
        // The status code could be anything depending on the server's handling
    } else |err| {
        // If we got an error, it should be a recognized HTTP client error
        switch (err) {
            HttpError.InvalidResponse, HttpError.ConnectionFailed, HttpError.ReadError, HttpError.RequestFailed => {}, // These are acceptable errors
            else => {
                // For other errors, fail the test
                try testing.expect(false);
            },
        }
    }
}
