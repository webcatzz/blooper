//! The main loop.

const builtin = @import("builtin");
const input = @import("input.zig");
const render = @import("render.zig");
const sokol = @import("sokol");
const std = @import("std");

/// `true` if the program is being compiled for Wasm.
const is_wasm = builtin.target.cpu.arch.isWasm();
/// If `true`, apps will be passed a safe allocator during initialization.
///
/// Emulates the behavior of `std.start`.
const use_safe_allocator = !is_wasm and switch (builtin.optimize) {
    .debug, .safe => true,
    .fast, .small => !builtin.link_libc and builtin.single_threaded,
};

/// Initialization parameters passed to the program.
var _init: std.process.Init.Minimal = undefined;
/// The allocator implementation passed to apps during initialization if
/// `use_safe_allocator` is `true`.
var safe_allocator: std.heap.SafeAllocator = undefined;
/// The IO implementation used by the app.
var threaded_io: std.Io.Threaded = undefined;

/// Runs the application defined by `T`.
///
/// `T` should fulfill the following interface:
///
/// ```
/// fn init(std.mem.Allocator, std.Io) !T
/// fn deinit(*T) void
/// fn iter(*T) !void
/// fn respond(*T, comptime event_type: input.event.Type, input.event.of(event_type)) !void
/// ```
///
/// This function should not be called while another instance is still running.
pub fn run(comptime T: type, init: std.process.Init.Minimal) void {
    _init = init;

    const impl = struct {
        var state: T = undefined;

        fn sokolInit() callconv(.c) void {
            // Chooses allocator (emulates behavior of `std.start`)

            const gpa = if (use_safe_allocator) init: {
                safe_allocator = .init(std.heap.page_allocator, .{});
                break :init safe_allocator.allocator();
            } else if (builtin.link_libc)
                std.heap.c_allocator
            else if (is_wasm)
                std.heap.wasm_allocator
            else if (!builtin.single_threaded)
                std.heap.smp_allocator
            else
                unreachable;

            // Initializes IO

            threaded_io = .init(gpa, .{
                .argv0 = .init(.{ .vector = _init.args.vector }),
                .environ = .{ .block = _init.environ.block },
            });

            // Initializes Sokol

            sokol.gfx.setup(.{
                .environment = sokol.glue.environment(),
                .logger = .{ .func = sokol.log.func },
            });
            if (!sokol.gfx.isvalid())
                std.log.scoped(.sokol).err("Failed to initialize Sokol graphics backend", .{});

            sokol.audio.setup(.{
                .logger = .{ .func = sokol.log.func },
            });
            if (!sokol.audio.isvalid())
                std.log.scoped(.sokol).err("Failed to initialize Sokol audio backend", .{});

            // Initializes app

            state = T.init(gpa, threaded_io.io()) catch {
                if (@errorReturnTrace()) |trace|
                    std.debug.dumpErrorReturnTrace(trace);
                sokol.app.quit();
                return;
            };
        }

        fn sokolCleanup() callconv(.c) void {
            state.deinit();
            sokol.audio.shutdown();
            sokol.gfx.shutdown();

            threaded_io.deinit();
            if (use_safe_allocator)
                _ = safe_allocator.deinit();
        }

        fn sokolFrame() callconv(.c) void {
            state.iter() catch {
                if (@errorReturnTrace()) |trace|
                    std.debug.dumpErrorReturnTrace(trace);
                sokol.app.quit();
                return;
            };
        }

        fn sokolEvent(event: [*c]const sokol.app.Event) callconv(.c) void {
            (switch (event.*.type) {
                .KEY_DOWN => if (!event.*.key_repeat) state.respond(.button, .{
                    .button = buttonFromSokolKeycode(event.*.key_code) orelse return,
                    .is_pressed = true,
                }),

                .KEY_UP => if (!event.*.key_repeat) state.respond(.button, .{
                    .button = buttonFromSokolKeycode(event.*.key_code) orelse return,
                    .is_pressed = false,
                }),

                .MOUSE_DOWN => state.respond(.button, .{
                    .button = buttonFromSokolMouseButton(event.*.mouse_button) orelse return,
                    .is_pressed = true,
                }),

                .MOUSE_UP => state.respond(.button, .{
                    .button = buttonFromSokolMouseButton(event.*.mouse_button) orelse return,
                    .is_pressed = false,
                }),

                .MOUSE_MOVE => state.respond(.cursor, .{
                    .pos = .{
                        .x = @divTrunc(@as(i32, @trunc(event.*.mouse_x)), render.scale),
                        .y = @divTrunc(@as(i32, @trunc(event.*.mouse_y)), render.scale),
                    },
                }),

                .MOUSE_SCROLL => state.respond(.scroll, .{
                    .amount = .{
                        .x = event.*.scroll_x,
                        .y = event.*.scroll_y,
                    },
                }),

                .CHAR => state.respond(.char, .{
                    .char = event.*.char_code,
                }),

                else => return,
            }) catch {
                if (@errorReturnTrace()) |trace|
                    std.debug.dumpErrorReturnTrace(trace);
                sokol.app.quit();
                return;
            };
        }
    };

    sokol.app.run(.{
        .window_title = "blooper",
        .width = 800,
        .height = 600,
        .init_cb = impl.sokolInit,
        .cleanup_cb = impl.sokolCleanup,
        .frame_cb = impl.sokolFrame,
        .event_cb = impl.sokolEvent,
        .logger = .{ .func = sokol.log.func },
    });
}

/// Exits the currently running main loop.
pub fn quit() void {
    sokol.app.quit();
}

/// Returns the button ID corresponding to the given Sokol keycode, or `null`.
fn buttonFromSokolKeycode(keycode: sokol.app.Keycode) ?input.Button {
    return switch (keycode) {
        .SPACE => .key_space,
        .A => .key_a,
        .B => .key_b,
        .C => .key_c,
        .D => .key_d,
        .E => .key_e,
        .F => .key_f,
        .G => .key_g,
        .H => .key_h,
        .I => .key_i,
        .J => .key_j,
        .K => .key_k,
        .L => .key_l,
        .M => .key_m,
        .N => .key_n,
        .O => .key_o,
        .P => .key_p,
        .Q => .key_q,
        .R => .key_r,
        .S => .key_s,
        .T => .key_t,
        .U => .key_u,
        .V => .key_v,
        .W => .key_w,
        .X => .key_x,
        .Y => .key_y,
        .Z => .key_z,
        ._0 => .key_0,
        ._1 => .key_1,
        ._2 => .key_2,
        ._3 => .key_3,
        ._4 => .key_4,
        ._5 => .key_5,
        ._6 => .key_6,
        ._7 => .key_7,
        ._8 => .key_8,
        ._9 => .key_9,
        .ESCAPE => .key_escape,
        .ENTER => .key_enter,
        .TAB => .key_tab,
        .BACKSPACE => .key_backspace,
        .RIGHT => .key_right,
        .LEFT => .key_left,
        .DOWN => .key_down,
        .UP => .key_up,
        .LEFT_SHIFT => .key_lshift,
        .LEFT_CONTROL => .key_lctrl,
        .LEFT_ALT => .key_lalt,
        .LEFT_SUPER => .key_lsuper,
        .RIGHT_SHIFT => .key_rshift,
        .RIGHT_CONTROL => .key_rctrl,
        .RIGHT_ALT => .key_ralt,
        .RIGHT_SUPER => .key_rsuper,
        else => null,
    };
}

/// Returns the button ID corresponding to the given Sokol mouse button, or
/// `null`.
fn buttonFromSokolMouseButton(mouse_button: sokol.app.Mousebutton) ?input.Button {
    return switch (mouse_button) {
        .LEFT, .RIGHT, .MIDDLE => @fromBackingInt(@as(u8, @intCast(@backingInt(mouse_button))) + @backingInt(input.Button.mouse_left)),
        else => null,
    };
}
