#include <metal_stdlib>
using namespace metal;

#include "ShaderTypes.h"

// MARK: - Heatmap Ground Quad Shaders
// Renders a textured ground-plane quad with a CPU-generated heatmap RGBA texture.

struct HeatmapVertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// MARK: - Vertex Shader

vertex HeatmapVertexOut heatmap_vertex(
    uint vertexID [[vertex_id]],
    constant HeatmapVertex *vertices [[buffer(BufferIndexHeatmapVertices)]],
    constant Uniforms &uniforms [[buffer(BufferIndexUniforms)]]
) {
    HeatmapVertexOut out;

    HeatmapVertex v = vertices[vertexID];

    float4 worldPos = float4(v.position, 1.0);
    float4 viewPos = uniforms.viewMatrix * worldPos;
    out.position = uniforms.projectionMatrix * viewPos;
    out.texCoord = v.texCoord;

    return out;
}

// MARK: - Fragment Shader

fragment float4 heatmap_fragment(
    HeatmapVertexOut in [[stage_in]],
    texture2d<float> heatmapTexture [[texture(0)]]
) {
    constexpr sampler texSampler(mag_filter::linear, min_filter::linear);

    float4 color = heatmapTexture.sample(texSampler, in.texCoord);

    // Skip empty cells (transparent)
    if (color.a < 0.01) {
        discard_fragment();
    }

    // Texture already contains premultiplied RGBA from CPU-side color ramp
    return color;
}
