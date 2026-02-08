#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

// Buffer indices shared between Swift and Metal shaders
typedef enum {
    BufferIndexUniforms = 0,
    BufferIndexVertices = 1,
    BufferIndexModelMatrix = 2
} BufferIndex;

// Texture indices
typedef enum {
    TextureIndexColor = 0
} TextureIndex;

// Uniform data passed to shaders each frame
typedef struct {
    simd_float4x4 modelMatrix;
    simd_float4x4 viewMatrix;
    simd_float4x4 projectionMatrix;
} Uniforms;

// Per-vertex data (colored geometry)
typedef struct {
    simd_float3 position;
    simd_float4 color;
} Vertex;

// Per-vertex data for textured geometry
typedef struct {
    simd_float3 position;
    simd_float2 texCoord;
} TexturedVertex;

#endif /* ShaderTypes_h */
