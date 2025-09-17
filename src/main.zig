const use_docking = @import("build_options").docking;
const ig = if (use_docking) @import("cimgui_docking") else @import("cimgui");
const sokol = @import("sokol");
const shd = @import("shaders/triangle.glsl.zig");
const slog = sokol.log;
const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;
const simgui = sokol.imgui;
const std = @import("std");

const v2 = struct {
    pos: [3]f32,
};

const v2c = struct {
    pos: [3]f32,
    color: [4]f32,
};

const state = struct {
    var pass_action: sg.PassAction = .{};
    var b: bool = true;
    var bind: sg.Bindings = .{};
    var pip: sg.Pipeline = .{};
    var vertices: [3]v2c = [3]v2c{
        v2c{ .pos = .{ 0.0,  0.5,  0.5 }, .color = .{ 1.0, 0.0, 0.9, 1.0 } },
        v2c{ .pos = .{ 0.5, -0.5,  0.5 }, .color = .{ 0.0, 1.0, 0.9, 1.0 } },
        v2c{ .pos = .{ -0.5, -0.5, 0.5 }, .color = .{ 0.0, 0.0, 1.0, 1.0 } },
    };
    var show_w: bool = false;
    var mouse_pos: v2 = undefined;
};

fn point_in_triangle(p: v2, t: [3][3]f32) bool {
    const a = [2]f32{ t[2][0] - t[0][0], t[2][1] - t[0][1] };
    const b = [2]f32{ t[1][0] - t[0][0], t[1][1] - t[0][1] };
    const c = [2]f32{ p.pos[0] - t[0][0], p.pos[1] - t[0][1] };
    const inv = 1.0 / (
    //   a[0] * a[0] + a[1] * a[1] -> get d between a[0] and a[1]
        (a[0] * a[0] + a[1] * a[1]) * (b[0] * b[0] + b[1] * b[1]) -
        (a[0] * b[0] + a[1] * b[1]) * (a[0] * b[0] + a[1] * b[1]));
    const u = (
        (b[0] * b[0] + b[1] * b[1]) * (a[0] * c[0] + a[1] * c[1]) -
        (a[0] * b[0] + a[1] * b[1]) * (b[0] * c[0] + b[1] * c[1]))*inv;
    const v = (
        (a[0] * a[0] + a[1] * a[1]) * (b[0] * c[0] + b[1] * c[1]) -
        (a[0] * b[0] + a[1] * b[1]) * (a[0] * c[0] + a[1] * c[1]))*inv;
    return u >= 0 and v >= 0 and u + v <= 1;
}

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
    if (use_docking) {
        ig.igGetIO().*.ConfigFlags |= ig.ImGuiConfigFlags_DockingEnable;
    }
    // initialize vertex buffer with triangle vertices
    state.bind.vertex_buffers[0] = sg.makeBuffer(.{
        .size = @sizeOf([3]v2c),
        .usage = sg.BufferUsage{ .stream_update = true },
    });
    // initialize a shader and pipeline object
    state.pip = sg.makePipeline(.{
        .shader = sg.makeShader(shd.triangleShaderDesc(sg.queryBackend())),
        .layout = init: {
            var l = sg.VertexLayoutState{};
            l.attrs[shd.ATTR_triangle_position].format = .FLOAT3;
            l.attrs[shd.ATTR_triangle_color0].format = .FLOAT4;
            break :init l;
        },
    });

    // initialize imgui save
    const io = ig.igGetIO();
    io.*.IniFilename = "src/imgui.ini";

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

    state.mouse_pos.pos[0] = - 1.0 + (ig.igGetMousePos().x / @as(f32, @floatFromInt(sapp.width ()))) * 2.0;
    state.mouse_pos.pos[1] =   1.0 - (ig.igGetMousePos().y / @as(f32, @floatFromInt(sapp.height()))) * 2.0;
    // loop over v to get pos
    var tri: [3][3]f32 = undefined;
    for (state.vertices[0..3], 0..) |vert, i| tri[i] = vert.pos;
    if (ig.igIsMouseClicked(0) and point_in_triangle(state.mouse_pos, tri)) {
        state.show_w = true;
    }

    // ui-code
    if (ig.igBegin("STATUS", &state.b, ig.ImGuiWindowFlags_None)) {
        _ = ig.igColorEdit3("Background", &state.pass_action.colors[0].clear_value.r, ig.ImGuiColorEditFlags_None);
        _ = ig.igText("Dear ImGui Version: %s", ig.IMGUI_VERSION);
    } ig.igEnd();
    if (state.show_w) {
        if (ig.igBegin("TRIANGLE", &state.b, ig.ImGuiWindowFlags_None)) {
            _ = ig.igColorEdit3("Color1", &state.vertices[0].color, ig.ImGuiColorEditFlags_None);
            _ = ig.igColorEdit3("Color2", &state.vertices[1].color, ig.ImGuiColorEditFlags_None);
            _ = ig.igColorEdit3("Color3", &state.vertices[2].color, ig.ImGuiColorEditFlags_None);
            _ = ig.igDragFloat2Ex("Pos1", &state.vertices[0].pos[0], 0.1, -50, 50, "%.3f", ig.ImGuiColorEditFlags_None);
            _ = ig.igDragFloat2Ex("Pos2", &state.vertices[1].pos[0], 0.1, -50, 50, "%.3f", ig.ImGuiColorEditFlags_None);
            _ = ig.igDragFloat2Ex("Pos3", &state.vertices[2].pos[0], 0.1, -50, 50, "%.3f", ig.ImGuiColorEditFlags_None);
        } ig.igEnd();
    } // ig.igEnd();

    // update
    sg.updateBuffer(state.bind.vertex_buffers[0], sg.asRange(&state.vertices));

    // sokol-gfx pass
    sg.beginPass(.{
        .action = state.pass_action,
        .swapchain = sglue.swapchain()
    });

    sg.applyPipeline(state.pip);
    sg.applyBindings(state.bind);
    sg.draw(0, 3, 1);

    simgui.render();
    sg.endPass();
    sg.commit();
}

export fn cleanup() void {
    simgui.shutdown();
    sg.shutdown();
}

export fn event(ev: [*c]const sapp.Event) void {
    // forward input events to sokol-imgui
    _ = simgui.handleEvent(ev.*);
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
