const std = @import("std");
const log = std.log;
const WaitGroup = @import("WaitGroup.zig");
const c = @cImport({
    @cInclude("stdbool.h");
    @cInclude("stdlib.h");
    @cInclude("cronet_c.h");
    @cInclude("bidirectional_stream_c.h");
});

var read_buf: [32768:0]u8 = undefined;
var wg: WaitGroup = undefined;

pub fn main() !void {
    var cronetEngine = c.Cronet_Engine_Create();

    var engineParams = c.Cronet_EngineParams_Create();
    var userAgentC: [*:0]const u8 = "Cronet";
    c.Cronet_EngineParams_user_agent_set(engineParams, userAgentC);
    c.Cronet_EngineParams_enable_http2_set(engineParams, true);
    _ = c.Cronet_Engine_StartWithParams(cronetEngine, engineParams);
    c.Cronet_EngineParams_Destroy(engineParams);

    var streamEngine = c.Cronet_Engine_GetStreamEngine(cronetEngine);

    var callback: c.bidirectional_stream_callback = undefined;
    callback.on_stream_ready = &on_stream_ready;
    callback.on_response_headers_received = &on_response_headers_received;
    callback.on_read_completed = &on_read_completed;
    callback.on_response_trailers_received = &on_response_trailers_received;
    callback.on_succeded = &on_succeded;
    callback.on_failed = &on_failed;
    callback.on_canceled = &on_canceled;

    var stream = c.bidirectional_stream_create(streamEngine, null, &callback);

    const url = std.os.argv[1];

    const method: [*:0]const u8 = "GET";

    wg.start();

    _ = c.bidirectional_stream_start(stream, url, 0, method, null, true);

    wg.wait();

    _ = c.bidirectional_stream_destroy(stream);
    _ = c.Cronet_Engine_Shutdown(cronetEngine);
    c.Cronet_Engine_Destroy(cronetEngine);
}

fn on_stream_ready(stream: [*c]c.bidirectional_stream) callconv(.C) void {
    _ = stream;
    log.info("on_stream_ready_callback", .{});
}

fn on_response_headers_received(
    stream: [*c]c.bidirectional_stream,
    headers: [*c]const c.bidirectional_stream_header_array,
    negotiated_protocol: [*c]const u8,
) callconv(.C) void {
    log.info(
        "on_response_headers_received, negotiated_protocol={s}",
        .{negotiated_protocol},
    );
    var hdrP: [*]c.bidirectional_stream_header = undefined;
    hdrP = headers[0].headers;

    var headersSlice = hdrP[0..headers[0].count];
    for (headersSlice) |header| {
        var key = header.key;
        if (std.mem.span(key).len == 0) {
            continue;
        }
        var value = header.value;
        log.info("{s}: {s}", .{ key, value });
    }

    var buf = @ptrCast([*c]u8, &read_buf);
    _ = c.bidirectional_stream_read(stream, buf, read_buf.len);
}

fn on_read_completed(
    stream: [*c]c.bidirectional_stream,
    data: [*c]u8,
    bytesRead: c_int,
) callconv(.C) void {
    _ = bytesRead;
    log.info("on_read_completed", .{});

    log.info("{s}", .{data});

    var buf = @ptrCast([*c]u8, &read_buf);
    _ = c.bidirectional_stream_read(stream, buf, read_buf.len);
}

fn on_write_completed(
    stream: [*]c.bidirectional_stream,
    data: [*:0]const u8,
) callconv(.C) void {
    _ = stream;
    _ = data;
    log.info("on_write_completed", .{});
}

fn on_response_trailers_received(
    stream: [*c]c.bidirectional_stream,
    trailers: [*c]const c.bidirectional_stream_header_array,
) callconv(.C) void {
    _ = stream;
    _ = trailers;
    log.info("on_response_trailers_received", .{});
}

fn on_succeded(stream: [*c]c.bidirectional_stream) callconv(.C) void {
    _ = stream;
    log.info("on_succeded", .{});
    wg.finish();
}

fn on_failed(
    stream: [*c]c.bidirectional_stream,
    net_error: c_int,
) callconv(.C) void {
    _ = stream;
    log.info("on_failed", .{});
    log.info("net error: {}", .{net_error});
    wg.finish();
}

fn on_canceled(stream: [*c]c.bidirectional_stream) callconv(.C) void {
    _ = stream;
    log.info("on_canceled", .{});
    wg.finish();
}
