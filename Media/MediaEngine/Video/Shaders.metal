#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut videoVertex(
    uint vid [[vertex_id]],
    constant float4x4 &mvp [[buffer(0)]]
) {
    // Full-screen triangle strip in NDC: positions + UVs
    float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    float2 uvs[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
    };
    VertexOut out;
    out.position = mvp * float4(positions[vid], 0.0, 1.0);
    out.texCoord = uvs[vid];
    return out;
}

// BT.709 limited range YCbCr → RGB
fragment float4 videoFragmentNV12(
    VertexOut in [[stage_in]],
    texture2d<float> textureY [[texture(0)]],
    texture2d<float> textureUV [[texture(1)]]
) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float y = textureY.sample(s, in.texCoord).r;
    float2 uv = textureUV.sample(s, in.texCoord).rg;
    float cb = uv.x - 0.5;
    float cr = uv.y - 0.5;

    // Limited range
    y = (y - 16.0 / 255.0) * (255.0 / 219.0);

    float r = y + 1.5748 * cr;
    float g = y - 0.1873 * cb - 0.4681 * cr;
    float b = y + 1.8556 * cb;
    return float4(clamp(r, 0.0, 1.0), clamp(g, 0.0, 1.0), clamp(b, 0.0, 1.0), 1.0);
}
