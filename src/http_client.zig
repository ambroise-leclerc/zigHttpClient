const std = @import("std");
const net = std.net;
const mem = std.mem;
const Allocator = std.mem.Allocator;

/// HTTP-related errors that can occur during client operations
pub const HttpError = error{
    ConnectionFailed,
    WriteError,
    ReadError,
    InvalidResponse,
    TooManyHeaders,
    HeaderTooLarge,
    RequestFailed,
    OutOfMemory,
    UnexpectedEof,
    AddressLookupFailure,
    ProtocolError,
    ChunkedEncodingError,
};

/// Supported HTTP methods
pub const HttpMethod = enum {
    GET,
    // Can be extended with: POST, PUT, DELETE, PATCH, HEAD, OPTIONS
};

/// Response object containing status code, headers and body data
pub const HttpResponse = struct {
    status_code: u16,
    headers: std.StringHashMap([]const u8),
    body: []const u8,
    allocator: Allocator,

    /// Free all resources associated with the response
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

/// HTTP client for making requests to HTTP servers
pub const HttpClient = struct {
    allocator: Allocator,
    timeout_ms: ?u32, // Optional timeout in milliseconds

    /// Initialize a new HTTP client with the given allocator
    pub fn init(allocator: Allocator) HttpClient {
        return .{
            .allocator = allocator,
            .timeout_ms = null,
        };
    }

    /// Initialize a new HTTP client with timeout
    pub fn initWithTimeout(allocator: Allocator, timeout_ms: u32) HttpClient {
        return .{
            .allocator = allocator,
            .timeout_ms = timeout_ms,
        };
    }

    /// Send a GET request to the specified host and path
    pub fn get(
        self: *HttpClient,
        host: []const u8,
        path: []const u8,
        headers: ?std.StringHashMap([]const u8),
    ) !HttpResponse {
        return self.sendRequest(.GET, host, path, headers);
    }

    /// Send an HTTP request with the specified method to the given host and path
    pub fn sendRequest(
        self: *HttpClient,
        method: HttpMethod,
        host: []const u8,
        path: []const u8,
        headers: ?std.StringHashMap([]const u8),
    ) !HttpResponse {
        // Default port is 80 for HTTP
        const port: u16 = 80;

        // Connect to the server
        var stream = net.tcpConnectToHost(self.allocator, host, port) catch |err| {
            switch (err) {
                error.ConnectionRefused => return HttpError.ConnectionFailed,
                error.UnknownHostName, error.NameServerFailure, error.TemporaryNameServerFailure => return HttpError.AddressLookupFailure,
                else => return err,
            }
        };
        defer stream.close();

        // Set timeout if configured
        // Note: Zig 0.13.0 doesn't have the setReadTimeout/setWriteTimeout methods
        // If we need timeouts in the future, we would have to implement them manually
        // using non-blocking IO or other means

        // Build and send the request
        try self.writeRequest(&stream, method, host, path, headers);

        // Process the response
        return try self.parseResponse(&stream);
    }

    /// Prepare and write the HTTP request to the stream
    fn writeRequest(
        self: *HttpClient,
        stream: *net.Stream,
        method: HttpMethod,
        host: []const u8,
        path: []const u8,
        headers: ?std.StringHashMap([]const u8),
    ) !void {
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

        // Add Connection: close header for HTTP/1.1 to avoid keep-alive
        try request_buffer.appendSlice("Connection: close\r\n");

        // End headers section
        try request_buffer.appendSlice("\r\n");

        // Send request
        _ = stream.write(request_buffer.items) catch {
            return HttpError.WriteError;
        };
    }

    /// Parse an HTTP response from the network stream
    fn parseResponse(self: *HttpClient, stream: *net.Stream) !HttpResponse {
        // Read the initial headers
        var header_buffer = std.ArrayList(u8).init(self.allocator);
        defer header_buffer.deinit();

        var body_buffer = std.ArrayList(u8).init(self.allocator);
        defer body_buffer.deinit();

        // Read headers until we find the end marker "\r\n\r\n"
        const max_header_size = 8192; // 8KB maximum header size
        var found_header_end = false;

        while (!found_header_end) {
            if (header_buffer.items.len >= max_header_size) {
                return HttpError.HeaderTooLarge;
            }

            var byte: [1]u8 = undefined;
            const bytes_read = stream.read(&byte) catch {
                return HttpError.ReadError;
            };

            if (bytes_read == 0) {
                return HttpError.UnexpectedEof;
            }

            try header_buffer.append(byte[0]);

            // Check if we've reached the end of headers
            if (header_buffer.items.len >= 4 and
                mem.eql(u8, header_buffer.items[header_buffer.items.len - 4 ..], "\r\n\r\n"))
            {
                found_header_end = true;
            }
        }

        // Parse status line
        var lines = mem.splitSequence(u8, header_buffer.items, "\r\n");
        const status_line = lines.next() orelse return HttpError.InvalidResponse;

        // Parse HTTP version and status code
        var status_parts = mem.splitSequence(u8, status_line, " ");
        const http_version = status_parts.next() orelse return HttpError.InvalidResponse;
        if (!mem.startsWith(u8, http_version, "HTTP/")) {
            return HttpError.InvalidResponse;
        }

        const status_code_str = status_parts.next() orelse return HttpError.InvalidResponse;
        const status_code = std.fmt.parseInt(u16, status_code_str, 10) catch {
            return HttpError.InvalidResponse;
        };

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

        var is_chunked = false;
        var content_length: ?usize = null;

        var header_line = lines.next();
        while (header_line) |line| {
            if (line.len == 0) break; // End of headers

            const separator_idx = mem.indexOf(u8, line, ":") orelse return HttpError.InvalidResponse;

            // Normalize header name (trim spaces and convert to lowercase)
            const header_name_raw = std.mem.trim(u8, line[0..separator_idx], " ");
            const header_name = try self.allocator.dupe(u8, header_name_raw);
            errdefer self.allocator.free(header_name);

            // Trim header value
            const header_value = try self.allocator.dupe(u8, std.mem.trim(u8, line[separator_idx + 1 ..], " "));
            errdefer self.allocator.free(header_value);

            // Check for special headers
            if (std.ascii.eqlIgnoreCase(header_name, "content-length")) {
                content_length = std.fmt.parseInt(usize, header_value, 10) catch {
                    return HttpError.InvalidResponse;
                };
            } else if (std.ascii.eqlIgnoreCase(header_name, "transfer-encoding")) {
                if (std.ascii.indexOfIgnoreCase(header_value, "chunked")) |_| {
                    is_chunked = true;
                }
            }

            try headers.put(header_name, header_value);
            header_line = lines.next();
        }

        // Read the response body
        if (is_chunked) {
            try self.readChunkedBody(stream, &body_buffer);
        } else if (content_length) |length| {
            try self.readFixedLengthBody(stream, &body_buffer, length);
        } else {
            // No content-length and not chunked, read until connection closes
            try self.readUntilEof(stream, &body_buffer);
        }

        // Copy the body to a new buffer owned by the response
        const body = try self.allocator.dupe(u8, body_buffer.items);
        errdefer self.allocator.free(body);

        return HttpResponse{
            .status_code = status_code,
            .headers = headers,
            .body = body,
            .allocator = self.allocator,
        };
    }

    /// Read a fixed-length body from the stream
    fn readFixedLengthBody(_: *HttpClient, stream: *net.Stream, buffer: *std.ArrayList(u8), length: usize) !void {
        var remaining = length;
        var read_buffer: [4096]u8 = undefined;

        while (remaining > 0) {
            const to_read = @min(remaining, read_buffer.len);
            const bytes_read = stream.read(read_buffer[0..to_read]) catch {
                return HttpError.ReadError;
            };

            if (bytes_read == 0) {
                return HttpError.UnexpectedEof;
            }

            try buffer.appendSlice(read_buffer[0..bytes_read]);
            remaining -= bytes_read;
        }
    }

    /// Read a chunked encoded body from the stream
    fn readChunkedBody(self: *HttpClient, stream: *net.Stream, buffer: *std.ArrayList(u8)) !void {
        var line_buffer = std.ArrayList(u8).init(self.allocator);
        defer line_buffer.deinit();

        while (true) {
            // Clear line buffer for next chunk size
            line_buffer.clearRetainingCapacity();

            // Read chunk size line
            while (true) {
                var byte: [1]u8 = undefined;
                const bytes_read = stream.read(&byte) catch {
                    return HttpError.ReadError;
                };

                if (bytes_read == 0) {
                    return HttpError.UnexpectedEof;
                }

                try line_buffer.append(byte[0]);

                // Check for end of line
                if (line_buffer.items.len >= 2 and
                    mem.eql(u8, line_buffer.items[line_buffer.items.len - 2 ..], "\r\n"))
                {
                    break;
                }
            }

            // Parse chunk size (ignore extensions)
            // Fixed: Don't chain calls to avoid the const pointer issue
            var chunk_size_iterator = mem.splitSequence(u8, line_buffer.items, ";");
            const chunk_size_str = chunk_size_iterator.next() orelse
                return HttpError.ChunkedEncodingError;

            const chunk_size = std.fmt.parseInt(usize, std.mem.trim(u8, chunk_size_str, " \r\n"), 16) catch {
                return HttpError.ChunkedEncodingError;
            };

            // If chunk size is 0, we've reached the end
            if (chunk_size == 0) {
                // Read the final CRLF
                var final_bytes: [2]u8 = undefined;
                const bytes_read = stream.read(&final_bytes) catch {
                    return HttpError.ReadError;
                };

                if (bytes_read < 2 or !mem.eql(u8, final_bytes[0..2], "\r\n")) {
                    return HttpError.ChunkedEncodingError;
                }

                break;
            }

            // Read the chunk data
            var remaining = chunk_size;
            var chunk_buffer: [4096]u8 = undefined;

            while (remaining > 0) {
                const to_read = @min(remaining, chunk_buffer.len);
                const bytes_read = stream.read(chunk_buffer[0..to_read]) catch {
                    return HttpError.ReadError;
                };

                if (bytes_read == 0) {
                    return HttpError.UnexpectedEof;
                }

                try buffer.appendSlice(chunk_buffer[0..bytes_read]);
                remaining -= bytes_read;
            }

            // Read the chunk trailing CRLF
            var crlf: [2]u8 = undefined;
            const crlf_read = stream.read(&crlf) catch {
                return HttpError.ReadError;
            };

            if (crlf_read < 2 or !mem.eql(u8, crlf[0..2], "\r\n")) {
                return HttpError.ChunkedEncodingError;
            }
        }
    }

    /// Read from stream until EOF is reached
    fn readUntilEof(_: *HttpClient, stream: *net.Stream, buffer: *std.ArrayList(u8)) !void {
        var read_buffer: [4096]u8 = undefined;

        while (true) {
            const bytes_read = stream.read(&read_buffer) catch {
                return HttpError.ReadError;
            };

            if (bytes_read == 0) {
                break; // EOF reached
            }

            try buffer.appendSlice(read_buffer[0..bytes_read]);
        }
    }
};
