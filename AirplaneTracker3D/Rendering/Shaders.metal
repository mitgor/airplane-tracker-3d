#include <metal_stdlib>
using namespace metal;

#include "ShaderTypes.h"

struct VertexIn {
    float3 position [[attribute(0)]];
    float4 color    [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
};

vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                             constant Uniforms &uniforms [[buffer(BufferIndexUniforms)]]) {
    VertexOut out;
    float4 worldPosition = uniforms.modelMatrix * float4(in.position, 1.0);
    float4 viewPosition = uniforms.viewMatrix * worldPosition;
    out.position = uniforms.projectionMatrix * viewPosition;
    out.color = in.color;
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]]) {
    return in.color;
}

// MARK: - Textured tile shaders

struct TexturedVertexIn {
    float3 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct TexturedVertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex TexturedVertexOut vertex_textured(TexturedVertexIn in [[stage_in]],
                                         constant Uniforms &uniforms [[buffer(BufferIndexUniforms)]],
                                         constant float4x4 &modelMatrix [[buffer(BufferIndexModelMatrix)]]) {
    TexturedVertexOut out;
    float4 worldPosition = modelMatrix * float4(in.position, 1.0);
    float4 viewPosition = uniforms.viewMatrix * worldPosition;
    out.position = uniforms.projectionMatrix * viewPosition;
    out.texCoord = in.texCoord;
    return out;
}

fragment float4 fragment_textured(TexturedVertexOut in [[stage_in]],
                                   texture2d<float> colorTexture [[texture(TextureIndexColor)]]) {
    constexpr sampler texSampler(mag_filter::linear, min_filter::linear, mip_filter::linear);
    return colorTexture.sample(texSampler, in.texCoord);
}

fragment float4 fragment_placeholder(TexturedVertexOut in [[stage_in]]) {
    return float4(0.4, 0.4, 0.4, 1.0);
}

// MARK: - Retro green-tint fragment shader for flat tiles

fragment float4 fragment_retro_textured(TexturedVertexOut in [[stage_in]],
                                         texture2d<float> colorTexture [[texture(TextureIndexColor)]]) {
    constexpr sampler texSampler(mag_filter::linear, min_filter::linear);
    float4 texColor = colorTexture.sample(texSampler, in.texCoord);
    // Convert to grayscale, invert, and shift to green channel for retro CRT look
    float gray = 1.0 - (texColor.r * 0.3 + texColor.g * 0.59 + texColor.b * 0.11);
    return float4(0.0, gray * 0.8, 0.0, 1.0);
}
