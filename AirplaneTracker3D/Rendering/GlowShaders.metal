#include <metal_stdlib>
using namespace metal;

#include "ShaderTypes.h"

// MARK: - Glow Billboard Vertex/Fragment Shaders (Instanced)

struct GlowVertexOut {
    float4 position [[position]];
    float2 texCoord;
    float4 color;
    float opacity;
};

vertex GlowVertexOut glow_vertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant Uniforms &uniforms [[buffer(BufferIndexUniforms)]],
    constant GlowInstanceData *instances [[buffer(BufferIndexGlowInstances)]]
) {
    GlowVertexOut out;

    constant GlowInstanceData &inst = instances[instanceID];

    // Billboard quad: 6 vertices (2 triangles) from vertexID
    // Corners: (-1,-1), (1,-1), (1,1), (-1,-1), (1,1), (-1,1)
    float2 corners[6] = {
        float2(-1, -1), float2(1, -1), float2(1, 1),
        float2(-1, -1), float2(1, 1),  float2(-1, 1)
    };
    float2 corner = corners[vertexID];

    // Texture coordinates (0-1)
    out.texCoord = corner * 0.5 + 0.5;

    // Extract camera right and up from view matrix columns
    float3 camRight = float3(uniforms.viewMatrix[0][0],
                              uniforms.viewMatrix[1][0],
                              uniforms.viewMatrix[2][0]);
    float3 camUp = float3(uniforms.viewMatrix[0][1],
                           uniforms.viewMatrix[1][1],
                           uniforms.viewMatrix[2][1]);

    // World position = instance center + billboard offsets
    float3 worldPos = inst.position
                    + camRight * corner.x * inst.size
                    + camUp * corner.y * inst.size;

    float4 viewPos = uniforms.viewMatrix * float4(worldPos, 1.0);
    out.position = uniforms.projectionMatrix * viewPos;

    out.color = inst.color;
    out.opacity = inst.opacity;

    return out;
}

fragment float4 glow_fragment(
    GlowVertexOut in [[stage_in]],
    texture2d<float> glowTexture [[texture(0)]]
) {
    constexpr sampler texSampler(mag_filter::linear, min_filter::linear);
    float4 texSample = glowTexture.sample(texSampler, in.texCoord);
    float texAlpha = texSample.a * in.opacity;

    // Additive blending: premultiply color by alpha
    return float4(in.color.rgb * texAlpha, texAlpha);
}
