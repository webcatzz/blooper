//! Rendering.

const ase = @import("../../util/ase.zig");
const builtin = @import("builtin");
const loop = @import("loop.zig");
const math = @import("math.zig");
const shd_basic = @import("shd_basic");
const sokol = @import("sokol");
const std = @import("std");

/// A queue of rendering operations.
pub const Queue = struct {
    cmd_buf: std.ArrayList(Command) = .empty,
    vtx_buf: std.ArrayList(Vertex) = .empty,

    clip_stack: std.ArrayList(math.Rect(f32)) = .empty,

    _gpu_vtx_buf: sokol.gfx.Buffer,
    _gpu_img: sokol.gfx.Image,
    _gpu_view: sokol.gfx.View,
    _gpu_sampler: sokol.gfx.Sampler,
    _gpu_pipeline: sokol.gfx.Pipeline,

    /// Returns a new rendering queue.
    ///
    /// The queue is owned by the caller and should be freed by calling
    /// `deinit`.
    pub fn init() !Queue {
        const vtx_buf = sokol.gfx.makeBuffer(.{
            .size = @sizeOf(Vertex),
            .usage = .{ .vertex_buffer = true, .write_transient = true },
        });

        const img = try loadSpritesheet(loop.gpa, loop.io);

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

        const clip_stack: std.ArrayList(math.Rect(f32)) = try .initCapacity(loop.gpa, 64);
        errdefer clip_stack.deinit(loop.gpa);

        return .{
            .clip_stack = clip_stack,
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
        self.cmd_buf.deinit(loop.gpa);
        self.vtx_buf.deinit(loop.gpa);
        self.clip_stack.deinit(loop.gpa);
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
            try self.vtx_buf.ensureTotalCapacity(loop.gpa, self.vtx_buf.items.len + vertices.len);

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
        try self.cmd_buf.append(loop.gpa, .{ .draw = @intCast(vertices.len) });
    }

    pub fn drawSlice(self: *Queue, src: math.Rect(f32), pos: math.Vec2(f32)) !void {
        try self.drawSliceStretch(src, .{ .x = pos.x, .y = pos.y, .w = src.w, .h = src.h });
    }

    pub fn drawSliceStretch(self: *Queue, src: math.Rect(f32), dst: math.Rect(f32)) !void {
        const vertices: [4]Vertex = .{
            .{ .x = dst.x, .y = dst.y, .u = src.x, .v = src.y },
            .{ .x = dst.x + dst.w, .y = dst.y, .u = src.x + src.w, .v = src.y },
            .{ .x = dst.x, .y = dst.y + dst.h, .u = src.x, .v = src.y + src.h },
            .{ .x = dst.x + dst.w, .y = dst.y + dst.h, .u = src.x + src.w, .v = src.y + src.h },
        };
        try self.draw(&.{ vertices[0], vertices[1], vertices[3], vertices[0], vertices[3], vertices[2] });
    }

    pub fn drawSliceRepeat(self: *Queue, src: math.Rect(f32), dst: math.Rect(f32)) !void {
        // TODO repeat
        try self.drawSliceStretch(src, dst);
    }

    pub fn drawSlice9Patch(self: *Queue, src: math.Rect(f32), border: math.Sides(f32), dst: math.Rect(f32)) !void {
        const Slice = struct { off: f32, len: f32 };
        const SlicePair = struct { src: Slice, dst: Slice };

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

    pub fn drawSprite(self: *Queue, spr: Sprite, pos: math.Vec2(f32)) !void {
        try self.drawSlice(Sprite.info.get(spr).rect, pos);
    }

    pub fn drawSpriteStretch(self: *Queue, spr: Sprite, dst: math.Rect(f32)) !void {
        try self.drawSliceStretch(Sprite.info.get(spr).rect, dst);
    }

    pub fn drawSpriteRepeat(self: *Queue, spr: Sprite, dst: math.Rect(f32)) !void {
        try self.drawSliceRepeat(Sprite.info.get(spr).rect, dst);
    }

    pub fn drawSprite9Patch(self: *Queue, spr: Sprite, dst: math.Rect(f32)) !void {
        const info = Sprite.info.get(spr);
        try self.drawSlice9Patch(info.rect, info.border, dst);
    }

    pub fn drawText(self: *Queue, text: []const u8, pos: math.Vec2(f32)) !void {
        var x = pos.x;

        for (text) |char| {
            const spr: Sprite = switch (char) {
                'a'...'z' => @fromBackingInt(@intCast(char - 'a' + @backingInt(Sprite.font_a))),
                'A'...'Z' => @fromBackingInt(@intCast(char - 'A' + @backingInt(Sprite.font_a))),
                '0'...'9' => @fromBackingInt(@intCast(char - '0' + @backingInt(Sprite.font_0))),
                '#' => .font_hash,
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

    pub fn clip(self: *Queue, rect: math.Rect(f32)) !void {
        var intersection = rect;
        for (self.clip_stack.items) |clip_rect|
            intersection = intersection.intersect(clip_rect);

        try self.clip_stack.append(loop.gpa, intersection);
        try self.cmd_buf.append(loop.gpa, .{ .clip = intersection });
    }

    pub fn unclip(self: *Queue) !void {
        _ = self.clip_stack.pop();
        if (self.clip_stack.last()) |rect|
            try self.cmd_buf.append(loop.gpa, .{ .clip = rect })
        else
            try self.cmd_buf.append(loop.gpa, .unclip);
    }

    /// Submits all queued operations to be rendered and clears the queue.
    ///
    /// `scale` is a multiplier applied to all vertex positions.
    pub fn flush(self: *Queue, scale: f32) void {
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
            .ptr = &shd_basic.VertUniform{ .scale_mult = .{ scale / widthf(), scale / heightf() } },
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
                    sokol.gfx.applyScissorRectf(
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
                        width(),
                        height(),
                        true,
                    );
                },
            };

        sokol.gfx.endPass();
        sokol.gfx.commit();

        self.cmd_buf.clearRetainingCapacity();
        self.vtx_buf.clearRetainingCapacity();
        self.clip_stack.clearRetainingCapacity();
    }
};

pub const Sprite = enum {
    frame,
    tab_active,
    tab_inactive,
    button,
    button_focused,
    button_active,
    button_icon_play,
    button_icon_pause,
    field,
    field_focused,
    field_cursor,
    dropdown,
    dropdown_focused,
    dropdown_active,

    note_red,
    note_yellow,
    note_green,
    note_blue,
    note_purple,
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
    font_hash,

    const info: std.EnumArray(Sprite, Info) = .init(@import("spr_info"));

    const Info = struct {
        rect: math.Rect(f32),
        border: math.Sides(f32),
    };
};

/// A rendering operation.
const Command = union(enum) {
    draw: u32,
    clip: math.Rect(f32),
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
    return sokol.app.width();
}

/// Returns the height of the rendering viewport, in pixels.
pub fn height() i32 {
    return sokol.app.height();
}

/// Returns the width of the rendering viewport, in pixels.
pub fn widthf() f32 {
    return sokol.app.widthf();
}

/// Returns the height of the rendering viewport, in pixels.
pub fn heightf() f32 {
    return sokol.app.heightf();
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
