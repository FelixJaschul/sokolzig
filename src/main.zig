const use_docking = @import("build_options").docking;
const ig = if (use_docking) @import("cimgui_docking") else @import("cimgui");
const sokol = @import("sokol");
const slog = sokol.log;
const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;
const simgui = sokol.imgui;
const std = @import("std");

fn loadShader(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const data = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    // Ensure null termination for [*c]const u8
    return try std.mem.concat(allocator, u8, &.{ data, "\x00" });
}

// At compile time these files are read and included as []const u8
const vs_bytes = @embedFile("shaders/vert.metal");
const fs_bytes = @embedFile("shaders/frag.metal");

const Camera = struct {
    pos: [3]f32 = .{ 0, 2.5, 0 },
    rot: [3]f32 = .{ 0, 0, 0 },
    forward: [3]f32 = .{ 0, 0, -1 },
};

const Wall = struct {
    points: [2][2]f32,
    color: [4]f32,
    portal_id: ?i32,
};

const Sector = struct {
    floor_h: f32,
    ceil_h: f32,
    walls: []const Wall,
};

const Level = struct {
    sectors: []const Sector,
};

const state = struct {
    var pass_action: sg.PassAction = .{};
    var b: bool = true;
    var bind: sg.Bindings = .{};
    var pip: sg.Pipeline = .{};
    var camera: Camera = .{};
    var level: Level = .{
        .sectors = &.{
            .{
                .floor_h = 0,
                .ceil_h = 5,
                .walls = &.{
                    .{ .points = .{ .{ -5, -5 }, .{ 5, -5 } }, .color = .{ 1, 0, 0, 1 }, .portal_id = 1 },
                    .{ .points = .{ .{ 5, -5 }, .{ 5, 5 } }, .color = .{ 0, 1, 0, 1 }, .portal_id = null },
                    .{ .points = .{ .{ 5, 5 }, .{ -5, 5 } }, .color = .{ 0, 0, 1, 1 }, .portal_id = null },
                    .{ .points = .{ .{ -5, 5 }, .{ -5, -5 } }, .color = .{ 1, 1, 0, 1 }, .portal_id = null },
                },
            },
            .{
                .floor_h = 0,
                .ceil_h = 5,
                .walls = &.{
                    .{ .points = .{ .{ -5, -5 }, .{ 5, -5 } }, .color = .{ 1, 0, 1, 1 }, .portal_id = 0 },
                    .{ .points = .{ .{ 5, -5 }, .{ 5, 5 } }, .color = .{ 0, 1, 1, 1 }, .portal_id = null },
                    .{ .points = .{ .{ 5, 5 }, .{ -5, 5 } }, .color = .{ 1, 1, 1, 1 }, .portal_id = null },
                    .{ .points = .{ .{ -5, 5 }, .{ -5, -5 } }, .color = .{ 0, 0, 0, 1 }, .portal_id = null },
                },
            },
        },
    };
};

export fn init() void {
    // initialize sokol-gfx
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });
    // initialize sokol-imgui
    simgui.setup(.{
        .logger = .{ .func = slog.func },
    });
    const io = ig.igGetIO();
    if (use_docking) io.*.ConfigFlags |= ig.ImGuiConfigFlags_DockingEnable;
    io.*.IniFilename = "src/imgui.ini";

    const vs_src = sg.ShaderFunction{
        .source = vs_bytes.ptr,
        .entry  = "vertex_main",
    };
    const fs_src = sg.ShaderFunction{
        .source = fs_bytes.ptr,
        .entry  = "fragment_main",
    };

    // in init(), after shader setup
    state.pip = sg.makePipeline(.{
        .shader = sg.makeShader(sg.ShaderDesc{
            .vertex_func   = vs_src,
            .fragment_func = fs_src,
            .attrs = [16]sg.ShaderVertexAttr{
                .{ .glsl_name = "position" },
                .{ .glsl_name = "color" },
                .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{},
            },
            .uniform_blocks = [8]sg.ShaderUniformBlock{
                .{ .size = 64,
                    .stage = .VERTEX,
                    .glsl_uniforms = [_]sg.GlslShaderUniform{
                        .{ .glsl_name = "view_proj", .type = .MAT4 },
                        .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{},
                    },
                },
                .{}, .{}, .{}, .{}, .{}, .{}, .{},
            },
        }),
        .layout = .{
            .attrs = [_]sg.VertexAttrState{
                .{ .format = .FLOAT3 }, // position
            .{ .format = .FLOAT4 }, // color
            .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{},
            },
        },
        .primitive_type = .TRIANGLES,
        .index_type = .UINT32, // <- changed to 32-bit indices
    });

    // vertex buffer (streaming)
    state.bind.vertex_buffers[0] = sg.makeBuffer(.{
        .size = 1024 * 1024 * @sizeOf(f32),
        .usage = sg.BufferUsage{ .stream_update = true },
    });

    // index buffer (streaming + index intent)
    state.bind.index_buffer = sg.makeBuffer(.{
        .size = 1024 * 1024 * @sizeOf(u32),
        .usage = sg.BufferUsage{ .stream_update = true, .index_buffer = true },
    });


    // initial clear color
    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0.1, .g = 0.1, .b = 0.3, .a = 1.0 },
    };
}

export fn frame() void {
    // call simgui.newFrame() before any ImGui calls
    simgui.newFrame(.{
        .width = sapp.width(),
        .height = sapp.height(),
        .delta_time = sapp.frameDuration(),
        .dpi_scale = sapp.dpiScale(),
    });

    // UI
    if (ig.igBegin("STATUS", &state.b, 0)) {
        _ = ig.igColorEdit3("Background", &state.pass_action.colors[0].clear_value.r, 0);
        _ = ig.igText("Dear ImGui Version: %s", ig.IMGUI_VERSION);
        _ = ig.igText("POS: %f / %f / %f", state.camera.pos[0], state.camera.pos[1], state.camera.pos[2]);
    }
    ig.igEnd();

    const aspect = sapp.widthf() / sapp.heightf();
    const proj = perspective(45.0, aspect, 0.01, 100.0);
    const view = look_at(state.camera.pos, add(state.camera.pos, state.camera.forward), .{0,1,0});
    const view_proj = mul(proj, view);

    const current_sector = get_current_sector(state.level, state.camera.pos);
    if (current_sector) |sector_id| {
        std.debug.print("Current sector: {d}\n", .{sector_id});
    } else {
        std.debug.print("Outside of any sector\n", .{});
    }

    // --- dynamic buffers (handle OOM gracefully) ---
    const allocator = std.heap.page_allocator;
    var vertex_list = std.ArrayList(f32).initCapacity(allocator, 1024) catch {
        std.debug.print("OOM: vertex_list\n", .{});
        return;
    };
    defer vertex_list.deinit(allocator);

    var index_list = std.ArrayList(u32).initCapacity(allocator, 1024) catch {
        std.debug.print("OOM: index_list\n", .{});
        return;
    };
    defer index_list.deinit(allocator);

    var queue: [32]struct { sector_id: usize, x_min: i32, x_max: i32 } = undefined;
    var queue_len: usize = 0;

    if (current_sector) |sector_id| {
        queue[0] = .{ .sector_id = sector_id, .x_min = 0, .x_max = @intCast(sapp.width()) };
        queue_len = 1;
    }

    var vertex_offset: u32 = 0;

    while (queue_len > 0) {
        queue_len -= 1;
        const entry = queue[queue_len];
        const sector = state.level.sectors[entry.sector_id];

        for (sector.walls) |wall| {
            // transform / rotate / project (unchanged)
            const p1 = .{ wall.points[0][0] - state.camera.pos[0], wall.points[0][1] - state.camera.pos[2] };
            const p2 = .{ wall.points[1][0] - state.camera.pos[0], wall.points[1][1] - state.camera.pos[2] };
            const sin = std.math.sin(state.camera.rot[1]);
            const cos = std.math.cos(state.camera.rot[1]);
            const p1_rot = .{ p1[0] * cos - p1[1] * sin, p1[0] * sin + p1[1] * cos };
            const p2_rot = .{ p2[0] * cos - p2[1] * sin, p2[0] * sin + p2[1] * cos };
            if (p1_rot[1] <= 0 or p2_rot[1] <= 0) continue;
            const p1_proj = .{ -p1_rot[0] * 200 / p1_rot[1], 0 };
            const p2_proj = .{ -p2_rot[0] * 200 / p2_rot[1], 0 };

            var x1 = @as(i32, @intFromFloat(p1_proj[0] + sapp.widthf() / 2));
            var x2 = @as(i32, @intFromFloat(p2_proj[0] + sapp.widthf() / 2));
            if (x1 >= x2 or x2 < entry.x_min or x1 > entry.x_max) continue;
            x1 = @max(x1, entry.x_min);
            x2 = @min(x2, entry.x_max);

            if (wall.portal_id) |portal_id| {
                if (queue_len < queue.len) {
                    queue[queue_len] = .{ .sector_id = @intCast(portal_id), .x_min = x1, .x_max = x2 };
                    queue_len += 1;
                }
            }

            const wall_vertices = [_]f32{
                wall.points[0][0], sector.floor_h, wall.points[0][1],
                wall.color[0], wall.color[1], wall.color[2], wall.color[3],

                wall.points[1][0], sector.floor_h, wall.points[1][1],
                wall.color[0], wall.color[1], wall.color[2], wall.color[3],

                wall.points[1][0], sector.ceil_h, wall.points[1][1],
                wall.color[0], wall.color[1], wall.color[2], wall.color[3],

                wall.points[0][0], sector.ceil_h, wall.points[0][1],
                wall.color[0], wall.color[1], wall.color[2], wall.color[3],
            };
            const wall_indices: [6]u16 = .{ 0, 1, 2, 0, 2, 3 };

            for (wall_vertices) |v| {
                vertex_list.append(allocator, v) catch @panic("vertex_list OOM");
            }

            for (wall_indices) |i| {
                index_list.append(allocator, i) catch @panic("index_list OOM");
            }

            for (wall_indices) |idx| {
                index_list.append(allocator, @intCast(idx + vertex_offset))
                    catch @panic("index_list OOM");
            }

            vertex_offset += 4;
        }
    }

    // upload only used slices
    // std.debug.print("verts: {d}, indices: {d}\n", .{ vertex_list.items.len, index_list.items.len });
    sg.updateBuffer(state.bind.vertex_buffers[0], sg.asRange(vertex_list.items[0..vertex_list.items.len]));
    sg.updateBuffer(state.bind.index_buffer, sg.asRange(index_list.items[0..index_list.items.len]));

    // sokol/gfx rendering
    sg.beginPass(.{
        .action = state.pass_action,
        .swapchain = sglue.swapchain(),
    });

    sg.applyPipeline(state.pip);
    sg.applyBindings(state.bind);
    sg.applyUniforms(0, sg.asRange(&view_proj));
    sg.draw(0, @intCast(index_list.items.len), 1);

    simgui.render();
    sg.endPass();
    sg.commit();
}

fn point_side(p: [2]f32, a: [2]f32, b: [2]f32) f32 {
    return (p[0] - a[0]) * (b[1] - a[1]) - (p[1] - a[1]) * (b[0] - a[0]);
}

fn point_in_sector(sector: Sector, p: [2]f32) bool {
    for (sector.walls) |wall| {
        if (point_side(p, wall.points[0], wall.points[1]) > 0) {
            return false;
        }
    }
    return true;
}

fn get_current_sector(level: Level, pos: [3]f32) ?usize {
    for (level.sectors, 0..) |sector, i| {
        if (point_in_sector(sector, .{ pos[0], pos[2] })) {
            return i;
        }
    }
    return null;
}

fn perspective(fov_y: f32, aspect: f32, z_near: f32, z_far: f32) [16]f32 {
    const f = 1.0 / std.math.tan(fov_y * std.math.pi / 360.0);
    return [_]f32{
        f / aspect, 0, 0, 0,
        0, f, 0, 0,
        0, 0, (z_far + z_near) / (z_near - z_far), -1,
        0, 0, (2 * z_far * z_near) / (z_near - z_far), 0,
    };
}

fn look_at(eye: [3]f32, center: [3]f32, up: [3]f32) [16]f32 {
    const f = normalize(sub(center, eye));
    const s = normalize(cross(f, up));
    const u = cross(s, f);
    return [_]f32{
        s[0], u[0], -f[0], 0,
        s[1], u[1], -f[1], 0,
        s[2], u[2], -f[2], 0,
        -dot(s, eye), -dot(u, eye), dot(f, eye), 1,
    };
}

fn mul(a: [16]f32, b: [16]f32) [16]f32 {
    var res: [16]f32 = undefined;
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        var j: usize = 0;
        while (j < 4) : (j += 1) {
            res[i * 4 + j] = a[i * 4 + 0] * b[0 * 4 + j] +
                a[i * 4 + 1] * b[1 * 4 + j] +
                a[i * 4 + 2] * b[2 * 4 + j] +
                a[i * 4 + 3] * b[3 * 4 + j];
        }
    }
    return res;
}

fn normalize(v: [3]f32) [3]f32 {
    const l = 1.0 / std.math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    return .{ v[0] * l, v[1] * l, v[2] * l };
}

fn sub(a: [3]f32, b: [3]f32) [3]f32 {
    return .{ a[0] - b[0], a[1] - b[1], a[2] - b[2] };
}

fn add(a: [3]f32, b: [3]f32) [3]f32 {
    return .{ a[0] + b[0], a[1] + b[1], a[2] + b[2] };
}

fn cross(a: [3]f32, b: [3]f32) [3]f32 {
    return .{ a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0] };
}

fn dot(a: [3]f32, b: [3]f32) f32 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

export fn cleanup() void {
    simgui.shutdown();
    sg.shutdown();
}

export fn event(ev: [*c]const sapp.Event) void {
    // forward input events to sokol-imgui
    _ = simgui.handleEvent(ev.*);
    if (ev.*.type == .KEY_DOWN) {
        switch (ev.*.key_code) {
            .UP => state.camera.pos = add(state.camera.pos, state.camera.forward),
            .DOWN => state.camera.pos = sub(state.camera.pos, state.camera.forward),
            .LEFT => state.camera.rot[1] -= 0.1,
            .RIGHT => state.camera.rot[1] += 0.1,
            else => {},
        }
        state.camera.forward = .{ std.math.sin(state.camera.rot[1]), 0, -std.math.cos(state.camera.rot[1]) };
    }
}

pub fn main() void {
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = event,
        .window_title = "DEMO",
        .width = 1400,
        .height = 800,
        .icon = .{ .sokol_default = true },
        .logger = .{ .func = slog.func },
    });
}
