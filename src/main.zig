const std = @import("std");
const HTTPClient = @import("http_client.zig").HTTPClient;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected!\n", .{});
        } else {
            std.debug.print("No memory leaks detected.\n", .{});
        }
    }

    const allocator = gpa.allocator();

    var client = HTTPClient.init(allocator, "httpbin.org", 80);

    // Optional headers
    var headers = std.StringHashMap([]const u8).init(allocator);
    defer headers.deinit();
    try headers.put("User-Agent", "Zig HTTP Client");

    var response = try client.get("/get", headers);
    defer response.deinit();

    std.debug.print("Status: {d}\n", .{response.status_code});

    // Print headers
    std.debug.print("\nHeaders:\n", .{});
    var header_it = response.headers.iterator();
    while (header_it.next()) |entry| {
        std.debug.print("{s}: {s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }

    std.debug.print("\nBody:\n{s}\n", .{response.body});
}
