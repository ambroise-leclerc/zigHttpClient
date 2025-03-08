# Zig HTTP Client

A lightweight, dependency-free HTTP client implementation in Zig. This library provides a simple way to make HTTP requests with minimal overhead.

## Features

- Simple API for making HTTP requests
- Support for custom headers
- Automatic handling of chunked transfer encoding
- Proper error handling with detailed error types
- Timeout support (configurable)
- Memory-safe implementation using Zig's allocator pattern

## Requirements

- Zig 0.13.0 or later

## Installation

You can include this library in your Zig project in several ways:

### Option 1: Git Submodule

```bash
# Add as a submodule to your project
git submodule add https://github.com/yourusername/zig-http-client.git lib/http-client

# Then in your build.zig:
exe.addPackagePath("http-client", "lib/http-client/http_client.zig");
```

### Option 2: Copy Files

Simply copy the `http_client.zig` file to your project directory and import it directly.

## Usage Examples

### Basic GET Request

```zig
const std = @import("std");
const HttpClient = @import("http_client.zig").HttpClient;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = HttpClient.init(allocator);

    // Make a simple GET request
    const response = try client.get("httpbin.org", "/get", null);
    defer response.deinit(); // Don't forget to free resources

    // Print status code and body
    std.debug.print("Status: {}\n", .{response.status_code});
    std.debug.print("Body: {s}\n", .{response.body});
}
```

### Adding Custom Headers

```zig
const std = @import("std");
const HttpClient = @import("http_client.zig").HttpClient;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = HttpClient.init(allocator);

    // Create custom headers
    var headers = std.StringHashMap([]const u8).init(allocator);
    defer headers.deinit();
    try headers.put("User-Agent", "Zig-HTTP-Client/0.1");
    try headers.put("Accept", "application/json");

    // Make request with custom headers
    const response = try client.get("httpbin.org", "/get", headers);
    defer response.deinit();

    // Print response headers
    var header_it = response.headers.iterator();
    while (header_it.next()) |entry| {
        std.debug.print("{s}: {s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }
}
```

### Handling Errors

```zig
const std = @import("std");
const HttpClient = @import("http_client.zig").HttpClient;
const HttpError = @import("http_client.zig").HttpError;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = HttpClient.init(allocator);

    // Try to access a non-existent domain
    const result = client.get("non-existent-domain.invalid", "/", null);
    
    if (result) |response| {
        defer response.deinit();
        std.debug.print("Success! Status: {}\n", .{response.status_code});
    } else |err| {
        switch (err) {
            HttpError.AddressLookupFailure => std.debug.print("Domain not found\n", .{}),
            HttpError.ConnectionFailed => std.debug.print("Connection failed\n", .{}),
            else => std.debug.print("Error: {any}\n", .{err}),
        }
    }
}
```

### Setting a Timeout

```zig
const std = @import("std");
const HttpClient = @import("http_client.zig").HttpClient;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize with a 5-second timeout
    var client = HttpClient.initWithTimeout(allocator, 5000);

    // Make request
    const response = try client.get("httpbin.org", "/delay/3", null);
    defer response.deinit();

    std.debug.print("Status: {}\n", .{response.status_code});
}
```

## Compilation Instructions

### Building a Project That Uses This Library

1. Create your main.zig file using the examples above
2. Compile your project:

```bash
# Compile and run directly
zig run main.zig -I /path/to/library/directory

# Or build an executable
zig build-exe main.zig -I /path/to/library/directory -O ReleaseSafe
```

### Running Tests

The library includes a comprehensive test suite that verifies its functionality:

```bash
# Run the tests
zig test http_client_test.zig -I /path/to/library/directory
```

## Error Handling

The library defines several error types in the `HttpError` enumeration to provide detailed information about what went wrong:

- `ConnectionFailed`: Failed to establish a connection
- `AddressLookupFailure`: Failed to resolve hostname
- `WriteError`: Failed to write to the connection
- `ReadError`: Failed to read from the connection
- `InvalidResponse`: Response format is invalid
- `HeaderTooLarge`: Headers exceed the maximum allowed size
- `UnexpectedEof`: Connection closed unexpectedly
- And more...

## Limitations

- Currently only supports HTTP (not HTTPS)
- Only implements the GET method (POST, PUT, etc. can be added)
- Does not follow redirects automatically
- Timeout functionality is declared but not fully implemented

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License (see LICENSE file for details)