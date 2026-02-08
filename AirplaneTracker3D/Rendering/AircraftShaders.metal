#include <metal_stdlib>
using namespace metal;

#include "ShaderTypes.h"

// MARK: - Aircraft Vertex/Fragment Shaders (Instanced)

struct AircraftVertexIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
};

struct AircraftVertexOut {
    float4 position [[position]];
    float3 worldNormal;
    float3 worldPosition;
    float4 color;
    float lightPhase;
    uint flags;
};

vertex AircraftVertexOut aircraft_vertex(
    AircraftVertexIn in [[stage_in]],
    constant Uniforms &uniforms [[buffer(BufferIndexUniforms)]],
    constant AircraftInstanceData *instances [[buffer(BufferIndexInstances)]],
    uint instanceID [[instance_id]]
) {
    AircraftVertexOut out;

    constant AircraftInstanceData &inst = instances[instanceID];

    // Transform vertex position by instance model matrix
    float4 worldPos = inst.modelMatrix * float4(in.position, 1.0);
    float4 viewPos = uniforms.viewMatrix * worldPos;
    out.position = uniforms.projectionMatrix * viewPos;

    // Transform normal (use upper-left 3x3 of model matrix, ignore translation)
    out.worldNormal = normalize((inst.modelMatrix * float4(in.normal, 0.0)).xyz);
    out.worldPosition = worldPos.xyz;
    out.color = inst.color;
    out.lightPhase = inst.lightPhase;
    out.flags = inst.flags;

    return out;
}

fragment float4 aircraft_fragment(AircraftVertexOut in [[stage_in]]) {
    // Directional lighting
    float3 lightDir = normalize(float3(0.5, 1.0, 0.5));
    float3 normal = normalize(in.worldNormal);
    float diffuse = max(dot(normal, lightDir), 0.0);
    float ambient = 0.3;
    float lighting = ambient + diffuse * 0.7;

    float3 litColor = in.color.rgb * lighting;

    // White strobe blink
    float strobe = step(0.7, sin(in.lightPhase)) * 0.2;
    litColor += float3(strobe);

    // Red beacon
    float beacon = step(0.5, sin(in.lightPhase * 0.6)) * 0.15;
    litColor += float3(beacon, 0.0, 0.0);

    // Selection highlight (gold)
    if (in.flags & 1u) {
        litColor = mix(litColor, float3(1.0, 0.8, 0.0), 0.3);
    }

    return float4(litColor, 1.0);
}
