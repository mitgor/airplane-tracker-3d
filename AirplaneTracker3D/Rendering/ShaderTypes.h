#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

// Buffer indices shared between Swift and Metal shaders
typedef enum {
    BufferIndexUniforms = 0,
    BufferIndexVertices = 1,
    BufferIndexModelMatrix = 2,
    BufferIndexInstances = 3,
    BufferIndexGlowInstances = 4
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

// Per-vertex data for aircraft geometry (position + normal)
typedef struct {
    simd_float3 position;
    simd_float3 normal;
} AircraftVertex;

// Per-instance data for aircraft rendering (96 bytes, GPU-aligned)
typedef struct {
    simd_float4x4 modelMatrix;   // 64 bytes: position + heading rotation
    simd_float4 color;           // 16 bytes: altitude-based RGBA
    float lightPhase;            // 4 bytes: position light animation phase
    float glowIntensity;         // 4 bytes: glow sprite pulse value (0.15-0.45)
    float rotorAngle;            // 4 bytes: rotor/propeller rotation (radians)
    unsigned int flags;          // 4 bytes: bitfield (bit 0 = selected)
} AircraftInstanceData;

// Per-instance data for glow sprites (48 bytes, GPU-aligned)
typedef struct {
    simd_float3 position;        // 12 bytes: world position
    float _pad0;                 // 4 bytes: padding
    simd_float4 color;           // 16 bytes: glow color
    float size;                  // 4 bytes: billboard size
    float opacity;               // 4 bytes: glow opacity
    float _pad1;                 // 4 bytes: padding
    float _pad2;                 // 4 bytes: padding
} GlowInstanceData;

#endif /* ShaderTypes_h */
