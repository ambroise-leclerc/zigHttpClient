const std = @import("std");
const HttpClient = @import("http_client.zig").HttpClient;

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
