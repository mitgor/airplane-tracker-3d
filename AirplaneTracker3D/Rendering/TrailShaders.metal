#include <metal_stdlib>
using namespace metal;

#include "ShaderTypes.h"

// MARK: - Trail Polyline Vertex/Fragment Shaders (Screen-Space Extrusion)

struct TrailVertexOut {
    float4 position [[position]];
    float4 color;
};

vertex TrailVertexOut trail_vertex(
    uint vertexID [[vertex_id]],
    constant TrailVertex *vertices [[buffer(BufferIndexTrailVertices)]],
    constant Uniforms &uniforms [[buffer(BufferIndexUniforms)]],
    constant float &lineWidth [[buffer(BufferIndexModelMatrix)]],
    constant float2 &resolution [[buffer(BufferIndexInstances)]]
) {
    TrailVertexOut out;

    TrailVertex v = vertices[vertexID];

    // Project current, previous, and next positions to clip space
    float4x4 viewProj = uniforms.projectionMatrix * uniforms.viewMatrix;
    float4 clipCurrent = viewProj * float4(v.position, 1.0);
    float4 clipPrev    = viewProj * float4(v.prevPosition, 1.0);
    float4 clipNext    = viewProj * float4(v.nextPosition, 1.0);

    // Convert to NDC (normalized device coordinates)
    float2 ndcCurrent = clipCurrent.xy / clipCurrent.w;
    float2 ndcPrev    = clipPrev.xy / clipPrev.w;
    float2 ndcNext    = clipNext.xy / clipNext.w;

    // Compute direction in screen space
    // Handle degenerate cases where prev == current or next == current
    float2 dir;
    float2 dirFromPrev = ndcCurrent - ndcPrev;
    float2 dirToNext   = ndcNext - ndcCurrent;

    bool hasPrev = length(dirFromPrev) > 1e-6;
    bool hasNext = length(dirToNext) > 1e-6;

    if (hasPrev && hasNext) {
        // Average the two directions for a smooth miter
        dir = normalize(normalize(dirFromPrev) + normalize(dirToNext));
    } else if (hasPrev) {
        dir = normalize(dirFromPrev);
    } else if (hasNext) {
        dir = normalize(dirToNext);
    } else {
        // Degenerate: no direction, use arbitrary
        dir = float2(1.0, 0.0);
    }

    // Perpendicular normal in NDC
    float2 normal = float2(-dir.y, dir.x);

    // Offset in clip space: convert pixel width to NDC offset
    // resolution is in pixels, so lineWidth/resolution gives NDC offset
    float2 offset = normal * v.direction * lineWidth / resolution;

    out.position = clipCurrent;
    out.position.xy += offset * clipCurrent.w;
    out.color = v.color;

    return out;
}

fragment float4 trail_fragment(TrailVertexOut in [[stage_in]]) {
    return in.color;
}
