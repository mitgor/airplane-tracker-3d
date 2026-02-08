#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

// Buffer indices shared between Swift and Metal shaders
typedef enum {
    BufferIndexUniforms = 0,
    BufferIndexVertices = 1
} BufferIndex;

// Uniform data passed to shaders each frame
typedef struct {
    simd_float4x4 modelMatrix;
    simd_float4x4 viewMatrix;
    simd_float4x4 projectionMatrix;
} Uniforms;

// Per-vertex data
typedef struct {
    simd_float3 position;
    simd_float4 color;
} Vertex;

#endif /* ShaderTypes_h */
