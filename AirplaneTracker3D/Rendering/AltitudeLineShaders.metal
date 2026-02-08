#include <metal_stdlib>
using namespace metal;

#include "ShaderTypes.h"

// MARK: - Dashed Altitude Reference Line Vertex/Fragment Shaders

struct AltLineVertexOut {
    float4 position [[position]];
    float worldY;
};

vertex AltLineVertexOut altline_vertex(
    uint vertexID [[vertex_id]],
    constant AltLineVertex *vertices [[buffer(BufferIndexAltLineVertices)]],
    constant Uniforms &uniforms [[buffer(BufferIndexUniforms)]]
) {
    AltLineVertexOut out;

    AltLineVertex v = vertices[vertexID];

    float4 worldPos = float4(v.position, 1.0);
    float4 viewPos = uniforms.viewMatrix * worldPos;
    out.position = uniforms.projectionMatrix * viewPos;
    out.worldY = v.worldY;

    return out;
}

fragment float4 altline_fragment(
    AltLineVertexOut in [[stage_in]]
) {
    // Dashed pattern based on world Y position
    float pattern = fmod(abs(in.worldY), 2.0) / 2.0;
    if (pattern > 0.5) discard_fragment();

    // Semi-transparent gray
    return float4(0.5, 0.5, 0.5, 0.3);
}
