#include <metal_stdlib>
using namespace metal;

#include "ShaderTypes.h"

// MARK: - Airspace Volume Shaders
// Renders semi-transparent FAA Class B/C/D airspace volumes with fill and edge passes.

struct AirspaceVertexOut {
    float4 position [[position]];
    float4 color;
    float3 worldPosition;
    float3 cameraPosition;
};

// MARK: - Vertex Shader

vertex AirspaceVertexOut airspace_vertex(
    uint vertexID [[vertex_id]],
    constant AirspaceVertex *vertices [[buffer(BufferIndexAirspaceVertices)]],
    constant Uniforms &uniforms [[buffer(BufferIndexUniforms)]]
) {
    AirspaceVertexOut out;

    AirspaceVertex v = vertices[vertexID];

    float4 worldPos = float4(v.position, 1.0);
    float4 viewPos = uniforms.viewMatrix * worldPos;
    out.position = uniforms.projectionMatrix * viewPos;
    out.color = v.color;
    out.worldPosition = v.position;
    out.cameraPosition = uniforms.cameraPosition;

    return out;
}

// MARK: - Fill Fragment Shader (semi-transparent volume faces)

fragment float4 airspace_fill_fragment(
    AirspaceVertexOut in [[stage_in]]
) {
    float alpha = in.color.a;

    // Discard nearly invisible fragments
    if (alpha < 0.005) discard_fragment();

    // Clamp alpha to prevent over-saturation
    alpha = min(alpha, 0.5);

    // Premultiplied alpha output for correct blending
    return float4(in.color.rgb * alpha, alpha);
}

// MARK: - Edge Fragment Shader (wireframe outlines)

fragment float4 airspace_edge_fragment(
    AirspaceVertexOut in [[stage_in]]
) {
    // Edge lines use higher alpha from vertex color (~0.3)
    // Return as-is with premultiplied alpha
    float alpha = in.color.a;
    return float4(in.color.rgb * alpha, alpha);
}
