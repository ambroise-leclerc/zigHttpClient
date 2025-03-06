const std = @import("std");
const net = std.net;
const testing = std.testing;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

/// HTTPClient represents the main HTTP client structure
pub const HTTPClient = struct {
    allocator: Allocator,
    host: []const u8,
    port: u16,

    /// Initialize a new HTTP client
    ///
    /// Args:
    ///   - allocator: Memory allocator
    ///   - host: Server hostname or IP address
    ///   - port: Server port (default 80 for HTTP)
    pub fn init(allocator: Allocator, host: []const u8, port: u16) HTTPClient {
        return HTTPClient{
            .allocator = allocator,
            .host = host,
            .port = port,
        };
    }

    /// HTTPResponse represents the server's response
    pub const HTTPResponse = struct {
        allocator: Allocator,
        status_code: u16,
        headers: std.StringHashMap([]const u8),
        body: []const u8,

        /// Free memory associated with the response
        pub fn deinit(self: *HTTPResponse) void {
            // Free all header keys and values stored in the hash map
            var it = self.headers.iterator();
            while (it.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                self.allocator.free(entry.value_ptr.*);
            }
            // Free the hash map itself
            self.headers.deinit();
            // Free the body
            self.allocator.free(self.body);
        }
    };

    /// Perform a GET request to the specified path
    ///
    /// Args:
    ///   - path: The URL path to request
    ///   - headers: Optional additional headers
    pub fn get(self: *const HTTPClient, path: []const u8, headers: ?std.StringHashMap([]const u8)) !HTTPResponse {
        // Resolve hostname and establish TCP connection
        var stream = blk: {
            // Try to parse as IP address first
            if (net.Address.parseIp(self.host, self.port)) |addr| {
                break :blk try net.tcpConnectToAddress(addr);
            } else |_| {
                // If not an IP address, try as hostname
                break :blk try net.tcpConnectToHost(self.allocator, self.host, self.port);
            }
        };
        defer stream.close();

        // Build the request incrementally using an ArrayList
        var request_list = ArrayList(u8).init(self.allocator);
        defer request_list.deinit();

        // Add request line and host header
        try std.fmt.format(request_list.writer(), "GET {s} HTTP/1.1\r\n", .{path});
        try std.fmt.format(request_list.writer(), "Host: {s}\r\n", .{self.host});
        try std.fmt.format(request_list.writer(), "Connection: close\r\n", .{});

        // Add custom headers if provided
        if (headers) |hdrs| {
            var iterator = hdrs.iterator();
            while (iterator.next()) |entry| {
                try std.fmt.format(request_list.writer(), "{s}: {s}\r\n", .{ entry.key_ptr.*, entry.value_ptr.* });
            }
        }

        // Add empty line to indicate end of headers
        try request_list.appendSlice("\r\n");

        // Get the final request string
        const request = request_list.items;

        // Send request
        _ = try stream.write(request);

        // Read response
        return try parseResponse(self.allocator, &stream);
    }

    /// Parse HTTP response from the stream
    fn parseResponse(allocator: Allocator, stream: *net.Stream) !HTTPResponse {
        var buffer: [8192]u8 = undefined;
        var total_read: usize = 0;

        // Read first chunk to get headers
        const first_chunk = try stream.read(buffer[0..]);
        if (first_chunk == 0) return error.ConnectionClosed;
        total_read += first_chunk;

        // Find the header-body separator
        const header_end = std.mem.indexOf(u8, buffer[0..total_read], "\r\n\r\n") orelse {
            return error.IncompleteHeaders;
        };

        // Extract headers section
        const headers_section = buffer[0..header_end];

        // Continue reading body if needed
        while (total_read < buffer.len) {
            const bytes_read = try stream.read(buffer[total_read..]);
            if (bytes_read == 0) break; // End of stream
            total_read += bytes_read;
        }

        // Extract body section (after headers + separator)
        const body_start = header_end + 4; // Skip "\r\n\r\n"
        const body_section = buffer[body_start..total_read];

        // Parse status line and headers
        var header_lines = std.mem.split(u8, headers_section, "\r\n");
        const status_line = header_lines.next() orelse return error.InvalidResponse;

        // Extract status code
        var status_parts = std.mem.split(u8, status_line, " ");
        _ = status_parts.next(); // Skip HTTP version
        const status_code_str = status_parts.next() orelse return error.InvalidResponse;
        const status_code = try std.fmt.parseInt(u16, status_code_str, 10);

        // Parse headers
        var headers = std.StringHashMap([]const u8).init(allocator);
        errdefer {
            var it = headers.iterator();
            while (it.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.*);
            }
            headers.deinit();
        }

        // Make sure we also clean up body on error
        const body = try allocator.dupe(u8, body_section);
        errdefer allocator.free(body);

        while (header_lines.next()) |line| {
            if (line.len > 0) {
                const colon_pos = std.mem.indexOf(u8, line, ": ") orelse continue;

                // Make copies of both key and value
                const header_name_dup = try allocator.dupe(u8, line[0..colon_pos]);
                errdefer allocator.free(header_name_dup);

                const header_value_dup = try allocator.dupe(u8, line[colon_pos + 2 ..]);
                errdefer allocator.free(header_value_dup);

                // Store both in the hash map
                try headers.put(header_name_dup, header_value_dup);
            }
        }

        return HTTPResponse{
            .allocator = allocator,
            .status_code = status_code,
            .headers = headers,
            .body = body,
        };
    }
};

// Test function
test "HTTP GET request to httpbin" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer {
        const leaked = gpa.deinit();
        std.debug.assert(leaked == .ok);
    }

    const allocator = gpa.allocator();

    var client = HTTPClient.init(allocator, "httpbin.org", 80);

    // Optional headers
    var headers = std.StringHashMap([]const u8).init(allocator);
    defer headers.deinit();
    try headers.put("User-Agent", "Zig HTTP Client Test");

    var response = try client.get("/get", headers);
    defer response.deinit();

    try testing.expectEqual(@as(u16, 200), response.status_code);
    try testing.expect(response.body.len > 0);
}
