#include <metal_stdlib>

using namespace metal;

struct Uniforms {
    float4x4 modelViewProjectionMatrix;
    float3x3 normalMatrix;
};

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float3 normal;
};

vertex VertexOut mesh_vertex(VertexIn in [[stage_in]],
                             constant Uniforms &uniforms [[buffer(1)]]) {
    VertexOut out;
    out.position = uniforms.modelViewProjectionMatrix * float4(in.position, 1.0);
    out.normal = uniforms.normalMatrix * in.normal;
    return out;
}

fragment float4 mesh_fragment(VertexOut in [[stage_in]]) {
    // Flat shading: use face normal direction to pick a shade of gray
    float3 normal = normalize(in.normal);
    // Simple hemisphere lighting: map normal.y from [-1,1] to [0.2, 1.0]
    float shade = mix(0.2, 1.0, normal.y * 0.5 + 0.5);
    return float4(shade, shade, shade, 1.0);
}
