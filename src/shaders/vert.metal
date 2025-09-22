#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
    float4 color    [[attribute(1)]];
};

struct Uniforms {
    float4x4 view_proj;
};

struct VSOut {
    float4 pos   [[position]];
    float4 color;
};

vertex VSOut vertex_main(VertexIn in [[stage_in]],
                         constant Uniforms& u [[buffer(0)]])  // <-- buffer slot 0
{
    VSOut out;
    out.pos   = u.view_proj * float4(in.position, 1.0);
    out.color = in.color;
    return out;
}

fragment float4 fragment_main(VSOut in [[stage_in]]) {
    return in.color;
}
