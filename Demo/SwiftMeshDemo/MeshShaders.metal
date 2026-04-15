#include <metal_stdlib>

using namespace metal;

// Must match DebugMode raw values in MetalMeshView.swift
enum DebugMode: uint {
    Shaded       = 0,
    Normals      = 1,
    TexCoords    = 2,
    FrontFacing  = 3,
    FaceNormals  = 4,
    Depth        = 5,
    Checkerboard = 6,
    Barycentric  = 7,
};

struct Uniforms {
    float4x4 modelViewProjectionMatrix;
    float3x3 normalMatrix;
    uint debugMode;
};

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
    float2 texCoord [[attribute(2)]];
};

struct VertexOut {
    float4 position [[position]];
    float3 worldNormal;
    float3 worldPosition;
    float2 texCoord;
};

vertex VertexOut mesh_vertex(VertexIn in [[stage_in]],
                             constant Uniforms &uniforms [[buffer(1)]]) {
    VertexOut out;
    out.position = uniforms.modelViewProjectionMatrix * float4(in.position, 1.0);
    out.worldNormal = uniforms.normalMatrix * in.normal;
    out.worldPosition = in.position;
    out.texCoord = in.texCoord;
    return out;
}

fragment float4 mesh_fragment(VertexOut in [[stage_in]],
                              constant Uniforms &uniforms [[buffer(0)]],
                              bool front_facing [[front_facing]],
                              float3 barycentric_coord [[barycentric_coord]]) {
    float3 color;

    switch (DebugMode(uniforms.debugMode)) {

    case DebugMode::Shaded: {
        float3 normal = normalize(in.worldNormal);
        float shade = mix(0.2, 1.0, normal.y * 0.5 + 0.5);
        color = float3(shade);
        break;
    }

    case DebugMode::Normals: {
        color = (normalize(in.worldNormal) + 1.0) * 0.5;
        break;
    }

    case DebugMode::TexCoords: {
        color = float3(in.texCoord.x, in.texCoord.y, 0.0);
        break;
    }

    case DebugMode::FrontFacing: {
        color = front_facing ? float3(0.2, 1.0, 0.2) : float3(1.0, 0.2, 0.2);
        break;
    }

    case DebugMode::FaceNormals: {
        float3 dPdx = dfdx(in.worldPosition);
        float3 dPdy = dfdy(in.worldPosition);
        float3 faceNormal = normalize(cross(dPdx, dPdy));
        color = (faceNormal + 1.0) * 0.5;
        break;
    }

    case DebugMode::Depth: {
        float depth = length(in.worldPosition);
        depth = saturate(depth / 2.0);
        color = float3(1.0 - depth);
        break;
    }

    case DebugMode::Checkerboard: {
        float checkSize = 10.0;
        bool checkX = fmod(floor(in.texCoord.x * checkSize), 2.0) > 0.5;
        bool checkY = fmod(floor(in.texCoord.y * checkSize), 2.0) > 0.5;
        color = (checkX != checkY) ? float3(1, 1, 1) : float3(0.2, 0.2, 0.2);
        break;
    }

    case DebugMode::Barycentric: {
        color = barycentric_coord;
        break;
    }

    default:
        color = float3(1.0, 0.0, 1.0);
        break;
    }

    return float4(color, 1.0);
}
