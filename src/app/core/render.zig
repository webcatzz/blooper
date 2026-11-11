//! Rendering.
//!
//! Rendering operations are collected in a `Queue` and flushed to the GPU by
//! calling `Queue.flush`. All rendering operations take logical pixel
//! coordinates, which are scaled up on the GPU to true display coordinates.
//!
//! All rendering uses a single 255-by-255 spritesheet texture, which is loaded
//! when a `Queue` is initialized and used for the entirety of the queue's
//! lifetime. For convenience, all slices defined in the spritesheet file are
//! enumerated by `Sprite` and compiled in as constants during build time.
//!
//! `Queue` provides draw calls with varying levels of abstraction. The user may
//!
//! - draw arbitrary vertices,
//! - draw arbitrary slices of the spritesheet,
//! - or draw predefined `Sprite`s.

const ase = @import("../ase.zig");
const builtin = @import("builtin");
const math = @import("math.zig");
const shd_basic = @import("shd_basic");
const sokol = @import("sokol");
const std = @import("std");

/// A multiplier applied to all vertex positions.
pub const scale = 3;

/// A queue of rendering operations.
pub const Queue = struct {
    cmd_buf: std.ArrayList(Command) = .empty,
    vtx_buf: std.ArrayList(Vertex) = .empty,
    gpa: std.mem.Allocator,
    _gpu_vtx_buf: sokol.gfx.Buffer,
    _gpu_img: sokol.gfx.Image,
    _gpu_view: sokol.gfx.View,
    _gpu_sampler: sokol.gfx.Sampler,
    _gpu_pipeline: sokol.gfx.Pipeline,

    /// Returns a new rendering queue.
    ///
    /// The queue is owned by the caller and should be freed by calling
    /// `deinit`.
    pub fn init(gpa: std.mem.Allocator, io: std.Io) !Queue {
        const vtx_buf = sokol.gfx.makeBuffer(.{
            .size = @sizeOf(Vertex),
            .usage = .{ .vertex_buffer = true, .write_transient = true },
        });

        const img = try loadSpritesheet(gpa, io);

        const view = sokol.gfx.makeView(.{ .texture = .{ .image = img } });

        const sampler = sokol.gfx.makeSampler(.{});

        const shader = sokol.gfx.makeShader(shd_basic.basicShaderDesc(sokol.gfx.queryBackend()));

        const pipeline = sokol.gfx.makePipeline(init: {
            var desc: sokol.gfx.PipelineDesc = .{};
            desc.shader = shader;
            desc.layout.attrs[shd_basic.ATTR_basic_vert_pos] = .{ .format = .FLOAT2 };
            desc.layout.attrs[shd_basic.ATTR_basic_vert_uv] = .{ .format = .FLOAT2 };
            desc.colors[0].blend.enabled = true;
            desc.colors[0].blend.src_factor_rgb = .SRC_ALPHA;
            desc.colors[0].blend.dst_factor_rgb = .ONE_MINUS_SRC_ALPHA;
            break :init desc;
        });

        return .{
            .gpa = gpa,
            ._gpu_vtx_buf = vtx_buf,
            ._gpu_img = img,
            ._gpu_view = view,
            ._gpu_sampler = sampler,
            ._gpu_pipeline = pipeline,
        };
    }

    /// Frees the queue.
    ///
    /// The queue should not be used after calling this function.
    pub fn deinit(self: *Queue) void {
        self.cmd_buf.deinit(self.gpa);
        self.vtx_buf.deinit(self.gpa);
        sokol.gfx.destroyBuffer(self._gpu_vtx_buf);
        sokol.gfx.destroyImage(self._gpu_img);
        sokol.gfx.destroyView(self._gpu_view);
        sokol.gfx.destroySampler(self._gpu_sampler);
        sokol.gfx.destroyPipeline(self._gpu_pipeline);
        self.* = undefined;
    }

    /// Queues the given vertices to be drawn.
    pub fn draw(self: *Queue, vertices: []const Vertex) !void {
        if (vertices.len > self.vtx_buf.capacity - self.vtx_buf.items.len) {
            try self.vtx_buf.ensureTotalCapacity(self.gpa, self.vtx_buf.items.len + vertices.len);

            const gpu_vtx_buf = sokol.gfx.makeBuffer(.{
                .usage = .{ .vertex_buffer = true, .write_transient = true },
                .size = self.vtx_buf.capacity * @sizeOf(Vertex),
            });
            sokol.gfx.destroyBuffer(self._gpu_vtx_buf);
            self._gpu_vtx_buf = gpu_vtx_buf;
        }
        self.vtx_buf.appendSliceAssumeCapacity(vertices);

        if (self.cmd_buf.lastPtr()) |last_cmd|
            if (last_cmd.* == .draw) {
                last_cmd.draw += @intCast(vertices.len);
                return;
            };
        try self.cmd_buf.append(self.gpa, .{ .draw = @intCast(vertices.len) });
    }

    /// Draws the given slice of the spritesheet with `pos` at its top-left
    /// corner.
    pub fn drawSlice(self: *Queue, src: math.Rect(u8), pos: math.Vec2(i32)) !void {
        try self.drawSliceStretch(src, .{ .x = pos.x, .y = pos.y, .w = src.w, .h = src.h });
    }

    /// Draws the given slice of the spritesheet stretched to fill `dst`.
    pub fn drawSliceStretch(self: *Queue, src: math.Rect(u8), dst: math.Rect(i32)) !void {
        const vertices: [4]Vertex = .{ .{
            .x = @floatFromInt(dst.x),
            .y = @floatFromInt(dst.y),
            .u = src.x,
            .v = src.y,
        }, .{
            .x = @floatFromInt(dst.x + dst.w),
            .y = @floatFromInt(dst.y),
            .u = src.x + src.w,
            .v = src.y,
        }, .{
            .x = @floatFromInt(dst.x),
            .y = @floatFromInt(dst.y + dst.h),
            .u = src.x,
            .v = src.y + src.h,
        }, .{
            .x = @floatFromInt(dst.x + dst.w),
            .y = @floatFromInt(dst.y + dst.h),
            .u = src.x + src.w,
            .v = src.y + src.h,
        } };
        try self.draw(&.{ vertices[0], vertices[1], vertices[3], vertices[0], vertices[3], vertices[2] });
    }

    /// Draws the given slice of the spritesheet repeated to fill `dst`.
    pub fn drawSliceRepeat(self: *Queue, src: math.Rect(u8), dst: math.Rect(i32)) !void {
        // TODO repeat
        try self.drawSliceStretch(src, dst);
    }

    /// Draws the given slice of the spritesheet stretched to fill `dst` while
    /// preserving the size of its borders.
    pub fn drawSlice9Patch(self: *Queue, src: math.Rect(u8), border: math.Sides(u8), dst: math.Rect(i32)) !void {
        const SlicePair = struct {
            src: struct { off: u8, len: u8 },
            dst: struct { off: i32, len: i32 },
        };

        const h_slices: [3]SlicePair = .{ .{
            .src = .{ .off = src.x, .len = border.left },
            .dst = .{ .off = dst.x, .len = border.left },
        }, .{
            .src = .{ .off = src.x + border.left, .len = src.w - border.left - border.right },
            .dst = .{ .off = dst.x + border.left, .len = dst.w - border.left - border.right },
        }, .{
            .src = .{ .off = src.x + src.w - border.right, .len = border.right },
            .dst = .{ .off = dst.x + dst.w - border.right, .len = border.right },
        } };
        const v_slices: [3]SlicePair = .{ .{
            .src = .{ .off = src.y, .len = border.top },
            .dst = .{ .off = dst.y, .len = border.top },
        }, .{
            .src = .{ .off = src.y + border.top, .len = src.h - border.top - border.bottom },
            .dst = .{ .off = dst.y + border.top, .len = dst.h - border.top - border.bottom },
        }, .{
            .src = .{ .off = src.y + src.h - border.bottom, .len = border.bottom },
            .dst = .{ .off = dst.y + dst.h - border.bottom, .len = border.bottom },
        } };

        for (h_slices) |h_slice|
            for (v_slices) |v_slice|
                try self.drawSliceStretch(.{
                    .x = h_slice.src.off,
                    .y = v_slice.src.off,
                    .w = h_slice.src.len,
                    .h = v_slice.src.len,
                }, .{
                    .x = h_slice.dst.off,
                    .y = v_slice.dst.off,
                    .w = h_slice.dst.len,
                    .h = v_slice.dst.len,
                });
    }

    /// Draws the given sprite with `pos` at its top-left corner.
    pub fn drawSprite(self: *Queue, spr: Sprite, pos: math.Vec2(i32)) !void {
        try self.drawSlice(Sprite.info.get(spr).rect, pos);
    }

    /// Draws the given sprite stretched to fill `dst`.
    pub fn drawSpriteStretch(self: *Queue, spr: Sprite, dst: math.Rect(i32)) !void {
        try self.drawSliceStretch(Sprite.info.get(spr).rect, dst);
    }

    /// Draws the given sprite repeated to fill `dst`.
    pub fn drawSpriteRepeat(self: *Queue, spr: Sprite, dst: math.Rect(i32)) !void {
        try self.drawSliceRepeat(Sprite.info.get(spr).rect, dst);
    }

    /// Draws the given sprite stretched to fill `dst` while preserving the size
    /// of its borders.
    pub fn drawSprite9Patch(self: *Queue, spr: Sprite, dst: math.Rect(i32)) !void {
        const info = Sprite.info.get(spr);
        try self.drawSlice9Patch(info.rect, info.border, dst);
    }

    /// Draws the given string with `pos` at its top-left corner.
    pub fn drawText(self: *Queue, text: []const u8, pos: math.Vec2(i32)) !void {
        var x = pos.x;

        for (text) |char| {
            const spr: Sprite = switch (char) {
                '!'...'~' => @fromBackingInt(@intCast(char - '!' + @backingInt(Sprite.font_exclamation))),
                ' ' => {
                    x += 3;
                    continue;
                },

                else => continue,
            };

            const spr_rect = Sprite.info.get(spr).rect;
            try self.drawSlice(spr_rect, .{ .x = x, .y = pos.y });
            x += spr_rect.w - 1;
        }
    }

    /// Clips subsequent drawing operations to the given rectangle.
    pub fn clip(self: *Queue, rect: math.Rect(i32)) !void {
        try self.cmd_buf.append(self.gpa, .{ .clip = rect });
    }

    /// Ignores any previous clipping for subsequent drawing operations.
    pub fn unclip(self: *Queue) !void {
        try self.cmd_buf.append(self.gpa, .unclip);
    }

    /// Submits all queued operations to be rendered and clears the queue.
    pub fn flush(self: *Queue) void {
        if (self.vtx_buf.items.len > 0)
            sokol.gfx.writeBufferTransient(.{
                .src = .{ .data = .{
                    .ptr = self.vtx_buf.items.ptr,
                    .size = self.vtx_buf.items.len * @sizeOf(Vertex),
                } },
                .dst = .{ .buffer = self._gpu_vtx_buf },
            })
        else {
            @branchHint(.cold);
        }

        sokol.gfx.beginPass(.{
            .swapchain = sokol.glue.swapchain(),
            .action = init: {
                var pass_action: sokol.gfx.PassAction = .{};
                pass_action.colors[0].load_action = .CLEAR;
                pass_action.colors[0].clear_value = .{ .r = 0, .g = 0, .b = 0, .a = 1 };
                break :init pass_action;
            },
        });

        sokol.gfx.applyPipeline(self._gpu_pipeline);

        var bindings: sokol.gfx.Bindings = .{};
        bindings.vertex_buffers[0] = self._gpu_vtx_buf;
        bindings.views[shd_basic.VIEW_tex] = self._gpu_view;
        bindings.samplers[shd_basic.SMP_smp] = self._gpu_sampler;
        sokol.gfx.applyBindings(bindings);

        sokol.gfx.applyUniforms(shd_basic.UB_vert_uniform, .{
            .ptr = &shd_basic.VertUniform{ .scale_mult = .{ scale / sokol.app.widthf(), scale / sokol.app.heightf() } },
            .size = @sizeOf(shd_basic.VertUniform),
        });

        var vtx_i: u32 = 0;
        for (self.cmd_buf.items) |cmd|
            switch (cmd) {
                .draw => |vtx_count| {
                    sokol.gfx.draw(vtx_i, vtx_count, 1);
                    vtx_i += vtx_count;
                },

                .clip => |rect| {
                    sokol.gfx.applyScissorRect(
                        rect.x * scale,
                        rect.y * scale,
                        rect.w * scale,
                        rect.h * scale,
                        true,
                    );
                },

                .unclip => {
                    sokol.gfx.applyScissorRect(
                        0,
                        0,
                        sokol.app.width(),
                        sokol.app.height(),
                        true,
                    );
                },
            };

        sokol.gfx.endPass();
        sokol.gfx.commit();

        self.cmd_buf.clearRetainingCapacity();
        self.vtx_buf.clearRetainingCapacity();
    }
};

/// Predefined slices of the spritesheet.
///
/// The order of `font_*` fields is significant; they should be enumerated in
/// the same order as their corresponding characters so that converting from one
/// to the other can be optimized.
pub const Sprite = enum {
    panel,
    panel_inset,
    panel_ticks_v,
    tab_active,
    tab_inactive,
    button,
    button_hovered,
    button_active,
    button_icon_play,
    button_icon_stop,
    switch_off,
    switch_on,
    field,
    field_hovered,
    field_cursor,
    dropdown,
    dropdown_hovered,
    dropdown_active,

    scroll_track,
    scroll_thumb,
    scroll_ticks_v,
    scroll_ticks_h,

    note_red,
    note_yellow,
    note_green,
    note_blue,
    note_purple,
    pitch_highlight,
    sect_red,
    sect_yellow,
    sect_green,
    sect_blue,
    sect_purple,
    sect_note_red,
    sect_note_yellow,
    sect_note_green,
    sect_note_blue,
    sect_note_purple,
    playhead,
    outline,

    font_exclamation,
    font_quote,
    font_hash,
    font_dollar,
    font_percent,
    font_ampersand,
    font_apostrophe,
    font_lparen,
    font_rparen,
    font_asterisk,
    font_plus,
    font_comma,
    font_minus,
    font_period,
    font_slash,
    font_0,
    font_1,
    font_2,
    font_3,
    font_4,
    font_5,
    font_6,
    font_7,
    font_8,
    font_9,
    font_colon,
    font_semicolon,
    font_less,
    font_equals,
    font_greater,
    font_question,
    font_at,
    font_A,
    font_B,
    font_C,
    font_D,
    font_E,
    font_F,
    font_G,
    font_H,
    font_I,
    font_J,
    font_K,
    font_L,
    font_M,
    font_N,
    font_O,
    font_P,
    font_Q,
    font_R,
    font_S,
    font_T,
    font_U,
    font_V,
    font_W,
    font_X,
    font_Y,
    font_Z,
    font_lbracket,
    font_backslash,
    font_rbracket,
    font_caret,
    font_underscore,
    font_backtick,
    font_a,
    font_b,
    font_c,
    font_d,
    font_e,
    font_f,
    font_g,
    font_h,
    font_i,
    font_j,
    font_k,
    font_l,
    font_m,
    font_n,
    font_o,
    font_p,
    font_q,
    font_r,
    font_s,
    font_t,
    font_u,
    font_v,
    font_w,
    font_x,
    font_y,
    font_z,
    font_lbrace,
    font_pipe,
    font_rbrace,
    font_tilde,

    dbg_ui_flag_border,

    /// Descriptions of each sprite.
    pub const info: std.EnumArray(Sprite, Info) = .init(@import("spr_info"));

    /// A description of a sprite.
    const Info = struct {
        rect: math.Rect(u8),
        border: math.Sides(u8),
    };
};

/// A rendering operation.
const Command = union(enum) {
    draw: u32,
    clip: math.Rect(i32),
    unclip,
};

/// A chunk of data passed to the vertex shader.
///
/// Should be kept in sync with the shader implementation.
const Vertex = extern struct {
    x: f32,
    y: f32,
    u: f32,
    v: f32,
};

/// Returns the width of the rendering viewport, in pixels.
pub fn width() i32 {
    return @divTrunc(sokol.app.width(), scale);
}

/// Returns the height of the rendering viewport, in pixels.
pub fn height() i32 {
    return @divTrunc(sokol.app.height(), scale);
}

/// Loads the spritesheet.
fn loadSpritesheet(gpa: std.mem.Allocator, io: std.Io) !sokol.gfx.Image {
    const file = try std.Io.Dir.cwd().openFile(io, "res/spr.aseprite", .{});
    defer file.close(io);
    var file_buf: [32]u8 = undefined;
    var file_reader = file.reader(io, &file_buf);

    const img = try ase.read(&file_reader.interface, gpa, .{ .read_data = true });
    defer gpa.free(img.data);

    const gpu_img = sokol.gfx.makeImage(.{
        .type = ._2D,
        .width = img.width,
        .height = img.height,
        .usage = .{ .immutable = true, .write_unsealed = true },
    });

    sokol.gfx.writeImageUnsealed(.{
        .src = .{ .data = .{ .ptr = img.data.ptr, .size = img.data.len } },
        .dst = .{ .image = gpu_img },
    });

    sokol.gfx.sealImage(gpu_img);

    return gpu_img;
}
