#include <metal_stdlib>
using namespace metal;

#include "ShaderTypes.h"

// MARK: - Terrain Vertex/Fragment Shaders

struct TerrainVertexIn {
    float3 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
    float3 normal   [[attribute(2)]];
};

struct TerrainVertexOut {
    float4 position [[position]];
    float2 texCoord;
    float3 worldNormal;
    float3 worldPosition;
};

// Terrain vertices are already in world space (built from MapCoordinateSystem coordinates).
// No per-tile modelMatrix needed -- transform directly by view and projection matrices.
vertex TerrainVertexOut terrain_vertex(
    TerrainVertexIn in [[stage_in]],
    constant Uniforms &uniforms [[buffer(BufferIndexUniforms)]]
) {
    TerrainVertexOut out;

    float4 worldPos = float4(in.position, 1.0);
    float4 viewPos = uniforms.viewMatrix * worldPos;
    out.position = uniforms.projectionMatrix * viewPos;

    out.texCoord = in.texCoord;
    out.worldNormal = in.normal;
    out.worldPosition = in.position;

    return out;
}

// Terrain fragment with map tile texture and directional lighting.
fragment float4 terrain_fragment(
    TerrainVertexOut in [[stage_in]],
    texture2d<float> colorTexture [[texture(TextureIndexColor)]]
) {
    constexpr sampler texSampler(mag_filter::linear, min_filter::linear, mip_filter::linear);
    float4 texColor = colorTexture.sample(texSampler, in.texCoord);

    // Directional lighting
    float3 lightDir = normalize(float3(0.5, 1.0, 0.3));
    float3 normal = normalize(in.worldNormal);
    float diffuse = max(dot(normal, lightDir), 0.0);
    float lighting = 0.4 + diffuse * 0.6;

    return float4(texColor.rgb * lighting, 1.0);
}

// Terrain fragment placeholder for tiles still loading their map texture.
// Shows terrain shape with a muted green-gray color and lighting.
fragment float4 terrain_fragment_placeholder(
    TerrainVertexOut in [[stage_in]]
) {
    float3 baseColor = float3(0.45, 0.50, 0.45);

    // Directional lighting
    float3 lightDir = normalize(float3(0.5, 1.0, 0.3));
    float3 normal = normalize(in.worldNormal);
    float diffuse = max(dot(normal, lightDir), 0.0);
    float lighting = 0.4 + diffuse * 0.6;

    return float4(baseColor * lighting, 1.0);
}

// Retro terrain fragment: green-tinted CRT look with directional lighting.
// Reuses terrain_vertex -- only the fragment stage changes.
fragment float4 fragment_retro_terrain(
    TerrainVertexOut in [[stage_in]],
    texture2d<float> colorTexture [[texture(TextureIndexColor)]]
) {
    constexpr sampler texSampler(mag_filter::linear, min_filter::linear, mip_filter::linear);
    float4 texColor = colorTexture.sample(texSampler, in.texCoord);

    // Convert to grayscale and invert for retro look
    float gray = 1.0 - (texColor.r * 0.3 + texColor.g * 0.59 + texColor.b * 0.11);

    // Apply directional lighting
    float3 lightDir = normalize(float3(0.5, 1.0, 0.3));
    float3 normal = normalize(in.worldNormal);
    float diffuse = max(dot(normal, lightDir), 0.0);
    float lighting = 0.4 + diffuse * 0.6;

    return float4(0.0, gray * 0.8 * lighting, 0.0, 1.0);
}

// Retro terrain placeholder (no texture yet, wireframe shape in green).
fragment float4 fragment_retro_terrain_placeholder(
    TerrainVertexOut in [[stage_in]]
) {
    float3 lightDir = normalize(float3(0.5, 1.0, 0.3));
    float3 normal = normalize(in.worldNormal);
    float diffuse = max(dot(normal, lightDir), 0.0);
    float lighting = 0.4 + diffuse * 0.6;

    return float4(0.0, 0.15 * lighting, 0.0, 1.0);
}
