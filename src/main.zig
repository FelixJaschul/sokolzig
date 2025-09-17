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
    x: f32 = 0.0,
    y: f32 = 0.0,
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
        v2c{ .pos = .{ 0.0,  0.5,  0.5 }, .color = .{ 1.0, 0.0, 0.0, 1.0 } },
        v2c{ .pos = .{ 0.5, -0.5,  0.5 }, .color = .{ 0.0, 1.0, 0.0, 1.0 } },
        v2c{ .pos = .{ -0.5, -0.5, 0.5 }, .color = .{ 0.0, 0.0, 1.0, 1.0 } },
    };
    var show_w: bool = false;
    var mouse_pos: v2 = undefined;
};

fn pointInTriangle(p: v2, tri: [3][3]f32) bool {
    const v0 = [2]f32{ tri[2][0] - tri[0][0], tri[2][1] - tri[0][1] };
    const v1 = [2]f32{ tri[1][0] - tri[0][0], tri[1][1] - tri[0][1] };
    const v2a = [2]f32{ p.x - tri[0][0], p.y - tri[0][1] };
    const dot00 = v0[0]*v0[0] + v0[1]*v0[1];
    const dot01 = v0[0]*v1[0] + v0[1]*v1[1];
    const dot02 = v0[0]*v2a[0] + v0[1]*v2a[1];
    const dot11 = v1[0]*v1[0] + v1[1]*v1[1];
    const dot12 = v1[0]*v2a[0] + v1[1]*v2a[1];
    const invDenom = 1.0 / (dot00 * dot11 - dot01 * dot01);
    const u = (dot11 * dot02 - dot01 * dot12) * invDenom;
    const v = (dot00 * dot12 - dot01 * dot02) * invDenom;
    return (u >= 0) and (v >= 0) and (u + v < 1);
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
    io.*.IniFilename = "imgui.ini";

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

    state.mouse_pos = v2{
        .x = - 1.0 + (ig.igGetMousePos().x / @as(f32, @floatFromInt(sapp.width ()))) * 2.0,
        .y =   1.0 - (ig.igGetMousePos().y / @as(f32, @floatFromInt(sapp.height()))) * 2.0,
    };
    var tri: [3][3] f32 = undefined;
    // loop over v to get pos
    for (state.vertices[0..3], 0..) |vert, i| tri[i] = vert.pos;
    if (ig.igIsMouseClicked(0) and
        pointInTriangle(state.mouse_pos, tri)) { state.show_w = !state.show_w; }

    // ui-code
    if (ig.igBegin("STATUS", &state.b, ig.ImGuiWindowFlags_None)) {
        _ = ig.igColorEdit3("Background", &state.pass_action.colors[0].clear_value.r, ig.ImGuiColorEditFlags_None);
        _ = ig.igText("Dear ImGui Version: %s", ig.IMGUI_VERSION);
    }
    ig.igEnd();
    if (state.show_w) {
        if (ig.igBegin("TRIANGLE", &state.b, ig.ImGuiWindowFlags_None)) {
            _ = ig.igColorEdit3("Color1", &state.vertices[0].color, ig.ImGuiColorEditFlags_None);
            _ = ig.igColorEdit3("Color2", &state.vertices[1].color, ig.ImGuiColorEditFlags_None);
            _ = ig.igColorEdit3("Color3", &state.vertices[2].color, ig.ImGuiColorEditFlags_None);
            ig.igEnd();
        }
    }

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
        .width = 800,
        .height = 600,
        .icon = .{ .sokol_default = true },
        .logger = .{ .func = slog.func },
    });
}
