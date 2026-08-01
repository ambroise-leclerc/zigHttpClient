# Contributing

Thank you for your interest in contributing to this project!

## Prerequisites

- [Zig](https://ziglang.org/) 0.13.0 or later

## Building

To build the project:
```bash
zig build
```

## Formatting

Please ensure your code is formatted before submitting a pull request:
```bash
zig fmt
```

## Running Tests

This project includes two distinct test suites:

### Offline / Unit Tests
These tests run locally without requiring an internet connection.
```bash
zig build test
```

### Network Tests
These tests make real HTTP requests to external services (e.g., `httpbin.org`). They require an active internet connection and depend on the availability of third-party services. Consequently, they may fail intermittently or in restricted environments and are not guaranteed to pass in all CI or local setups.
```bash
zig build test-network
```

## Pull Requests

Please ensure all offline tests pass and your code is formatted before opening a pull request. Network test failures due to external service unavailability or timeouts do not necessarily indicate a problem with your changes.
