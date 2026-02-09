#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

// Buffer indices shared between Swift and Metal shaders
typedef enum {
    BufferIndexUniforms = 0,
    BufferIndexVertices = 1,
    BufferIndexModelMatrix = 2,
    BufferIndexInstances = 3,
    BufferIndexGlowInstances = 4,
    BufferIndexTrailVertices = 5,
    BufferIndexLabelInstances = 6,
    BufferIndexAltLineVertices = 7,
    BufferIndexAirspaceVertices = 8
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
    simd_float3 cameraPosition;    // World-space camera position (for Fresnel/specular)
    float _pad;                     // Alignment padding
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

// Per-vertex data for trail polyline rendering (64 bytes, GPU-aligned)
typedef struct {
    simd_float3 position;       // World position (12 bytes)
    float direction;            // +1 or -1 (which side of the strip) (4 bytes)
    simd_float4 color;          // Altitude-based color per-vertex (16 bytes)
    simd_float3 prevPosition;   // Previous point for direction calc (12 bytes)
    float _pad0;                // Padding (4 bytes)
    simd_float3 nextPosition;   // Next point for direction calc (12 bytes)
    float _pad1;                // Padding (4 bytes)
} TrailVertex;
// Total: 64 bytes, naturally aligned

// Per-instance data for billboard label rendering (48 bytes, GPU-aligned)
typedef struct {
    simd_float3 position;    // 12 bytes: world position (above aircraft)
    float size;              // 4 bytes: billboard size
    simd_float2 atlasUV;    // 8 bytes: UV offset into atlas (top-left corner)
    simd_float2 atlasSize;  // 8 bytes: UV size of this label's slot in atlas
    float opacity;           // 4 bytes: distance-based fade (LOD)
    float _pad0;             // 4 bytes: padding
    float _pad1;             // 4 bytes: padding
    float _pad2;             // 4 bytes: padding
} LabelInstanceData;
// Total: 48 bytes

// Per-vertex data for altitude reference lines (32 bytes)
typedef struct {
    simd_float3 position;    // 12 bytes: world position
    float worldY;            // 4 bytes: Y value for dash pattern
    simd_float4 color;       // 16 bytes: theme-aware RGBA color
} AltLineVertex;
// Total: 32 bytes

// Per-vertex data for terrain mesh (position + texCoord + normal)
typedef struct {
    simd_float3 position;   // XYZ with Y = displaced elevation
    simd_float2 texCoord;   // UV for map tile texture sampling
    simd_float3 normal;     // Computed surface normal for lighting
} TerrainVertex;

// Per-vertex data for airspace volume rendering (32 bytes)
typedef struct {
    simd_float3 position;    // 12 bytes: world-space XYZ
    float _pad0;             // 4 bytes: padding for alignment
    simd_float4 color;       // 16 bytes: per-vertex RGBA (class color with alpha)
} AirspaceVertex;
// Total: 32 bytes

#endif /* ShaderTypes_h */
