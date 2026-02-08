#include <metal_stdlib>
using namespace metal;

#include "ShaderTypes.h"

// MARK: - Billboard Label Vertex/Fragment Shaders (Instanced)

struct LabelVertexOut {
    float4 position [[position]];
    float2 texCoord;
    float opacity;
};

vertex LabelVertexOut label_vertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant Uniforms &uniforms [[buffer(BufferIndexUniforms)]],
    constant LabelInstanceData *instances [[buffer(BufferIndexLabelInstances)]]
) {
    LabelVertexOut out;

    constant LabelInstanceData &inst = instances[instanceID];

    // Billboard quad: 6 vertices (2 triangles) from vertexID
    float2 corners[6] = {
        float2(-1, -1), float2(1, -1), float2(1, 1),
        float2(-1, -1), float2(1, 1),  float2(-1, 1)
    };
    float2 corner = corners[vertexID];

    // Texture coordinates mapped into atlas sub-region
    float2 uv01 = corner * 0.5 + 0.5;
    // Flip V so top of label maps to top of atlas slot
    uv01.y = 1.0 - uv01.y;
    out.texCoord = inst.atlasUV + uv01 * inst.atlasSize;

    // Extract camera right and up from view matrix columns
    float3 camRight = float3(uniforms.viewMatrix[0][0],
                              uniforms.viewMatrix[1][0],
                              uniforms.viewMatrix[2][0]);
    float3 camUp = float3(uniforms.viewMatrix[0][1],
                           uniforms.viewMatrix[1][1],
                           uniforms.viewMatrix[2][1]);

    // World position = instance center + billboard offsets
    // Labels are wider than tall (~4:1 aspect), so scale Y by 0.25
    float3 worldPos = inst.position
                    + camRight * corner.x * inst.size
                    + camUp * corner.y * inst.size * 0.25;

    float4 viewPos = uniforms.viewMatrix * float4(worldPos, 1.0);
    out.position = uniforms.projectionMatrix * viewPos;

    out.opacity = inst.opacity;

    return out;
}

fragment float4 label_fragment(
    LabelVertexOut in [[stage_in]],
    texture2d<float> atlasTexture [[texture(0)]]
) {
    constexpr sampler texSampler(mag_filter::linear, min_filter::linear);
    float4 texSample = atlasTexture.sample(texSampler, in.texCoord);

    // Apply distance fade
    float alpha = texSample.a * in.opacity;

    // Discard fully transparent fragments
    if (alpha < 0.01) discard_fragment();

    // Return premultiplied alpha for blending
    return float4(texSample.rgb * alpha, alpha);
}
