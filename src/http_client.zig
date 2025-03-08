const std = @import("std");
const net = std.net;
const mem = std.mem;
const Allocator = std.mem.Allocator;

pub const HttpError = error{
    ConnectionFailed,
    WriteError,
    ReadError,
    InvalidResponse,
    TooManyHeaders,
    HeaderTooLarge,
    RequestFailed,
};

pub const HttpMethod = enum {
    GET,
    // Could be extended with POST, PUT, etc.
};

pub const HttpResponse = struct {
    status_code: u16,
    headers: std.StringHashMap([]const u8),
    body: []const u8,
    allocator: Allocator,

    pub fn deinit(self: *const HttpResponse) void {
        // Free each header key and value
        var header_it = self.headers.iterator();
        while (header_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }

        // Create a non-const copy to deinit
        var headers_copy = self.headers;
        headers_copy.deinit();

        // Free the body
        self.allocator.free(self.body);
    }
};

pub const HttpClient = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) HttpClient {
        return .{ .allocator = allocator };
    }

    pub fn get(
        self: *HttpClient,
        host: []const u8,
        path: []const u8,
        headers: ?std.StringHashMap([]const u8),
    ) !HttpResponse {
        return self.sendRequest(.GET, host, path, headers);
    }

    pub fn sendRequest(
        self: *HttpClient,
        method: HttpMethod,
        host: []const u8,
        path: []const u8,
        headers: ?std.StringHashMap([]const u8),
    ) !HttpResponse {
        // Default port is 80
        const port: u16 = 80;

        // Connect to the server
        var stream = try net.tcpConnectToHost(self.allocator, host, port);
        defer stream.close();

        // Prepare request
        var request_buffer = std.ArrayList(u8).init(self.allocator);
        defer request_buffer.deinit();

        // Add request line
        try request_buffer.appendSlice(@tagName(method));
        try request_buffer.appendSlice(" ");
        try request_buffer.appendSlice(path);
        try request_buffer.appendSlice(" HTTP/1.1\r\n");

        // Add Host header
        try request_buffer.appendSlice("Host: ");
        try request_buffer.appendSlice(host);
        try request_buffer.appendSlice("\r\n");

        // Add user-defined headers
        if (headers) |user_headers| {
            var it = user_headers.iterator();
            while (it.next()) |entry| {
                try request_buffer.appendSlice(entry.key_ptr.*);
                try request_buffer.appendSlice(": ");
                try request_buffer.appendSlice(entry.value_ptr.*);
                try request_buffer.appendSlice("\r\n");
            }
        }

        // Add Connection: close header
        try request_buffer.appendSlice("Connection: close\r\n");

        // End headers section
        try request_buffer.appendSlice("\r\n");

        // Send request
        _ = try stream.write(request_buffer.items);

        // Read response
        return try self.parseResponse(&stream);
    }

    fn parseResponse(self: *HttpClient, stream: *net.Stream) !HttpResponse {
        var buffer: [4096]u8 = undefined;
        var response_buffer = std.ArrayList(u8).init(self.allocator);
        defer response_buffer.deinit();

        // Read the full response
        while (true) {
            const bytes_read = try stream.read(buffer[0..]);
            if (bytes_read == 0) break;
            try response_buffer.appendSlice(buffer[0..bytes_read]);
        }

        // Parse status line
        var lines = std.mem.split(u8, response_buffer.items, "\r\n");
        const status_line = lines.next() orelse return HttpError.InvalidResponse;

        // Parse HTTP version and status code
        var status_parts = std.mem.split(u8, status_line, " ");
        _ = status_parts.next(); // Skip HTTP version
        const status_code_str = status_parts.next() orelse return HttpError.InvalidResponse;
        const status_code = try std.fmt.parseInt(u16, status_code_str, 10);

        // Parse headers
        var headers = std.StringHashMap([]const u8).init(self.allocator);
        errdefer {
            var it = headers.iterator();
            while (it.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                self.allocator.free(entry.value_ptr.*);
            }
            headers.deinit();
        }

        var header_line = lines.next();
        var content_length: usize = 0;

        while (header_line) |line| {
            if (line.len == 0) break; // End of headers

            const separator_idx = std.mem.indexOf(u8, line, ":") orelse return HttpError.InvalidResponse;
            const header_name = try self.allocator.dupe(u8, std.mem.trim(u8, line[0..separator_idx], " "));
            errdefer self.allocator.free(header_name);

            const header_value = try self.allocator.dupe(u8, std.mem.trim(u8, line[separator_idx + 1 ..], " "));
            errdefer self.allocator.free(header_value);

            // Check for Content-Length header
            if (std.ascii.eqlIgnoreCase(header_name, "content-length")) {
                content_length = try std.fmt.parseInt(usize, header_value, 10);
            }

            try headers.put(header_name, header_value);
            header_line = lines.next();
        }

        // Extract body
        const headers_end_idx = if (std.mem.indexOf(u8, response_buffer.items, "\r\n\r\n")) |idx| idx + 4 else response_buffer.items.len;
        const body_data = response_buffer.items[headers_end_idx..];
        const body = try self.allocator.dupe(u8, body_data);

        return HttpResponse{
            .status_code = status_code,
            .headers = headers,
            .body = body,
            .allocator = self.allocator,
        };
    }
};

// Example usage function
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = HttpClient.init(allocator);

    // Optional headers
    var headers = std.StringHashMap([]const u8).init(allocator);
    defer headers.deinit();
    try headers.put("User-Agent", "Zig-HTTP-Client/0.1");

    // Make a GET request
    const response = try client.get("httpbin.org", "/get", headers);
    defer response.deinit();

    // Print response
    std.debug.print("Status: {}\n", .{response.status_code});
    std.debug.print("Body: {s}\n", .{response.body});

    // Print headers
    var header_it = response.headers.iterator();
    while (header_it.next()) |entry| {
        std.debug.print("{s}: {s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }
}
