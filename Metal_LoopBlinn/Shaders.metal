//
//  Shaders.metal
//  Metal_LoopBlinn
//
//  Created by randomyang on 2025/1/22.
//

#include <metal_stdlib>
using namespace metal;

// Vertex input
struct VertexIn {
    float3 position [[attribute(0)]];
    float2 uv [[attribute(1)]];
    float sign [[attribute(2)]];
    float4 color [[attribute(3)]];
};

// Vertex output
struct VertexOut {
    float4 position [[position]];
    float2 uv;
    float sign;
    float4 color;
};

// Vertex shader
vertex VertexOut vertexShader(
    VertexIn in [[stage_in]],
    constant float4x4 &transform [[buffer(1)]]
) {
    VertexOut out;
    out.position = transform * float4(in.position, 1.0); // Apply transform
    out.uv = in.uv;
    out.sign = in.sign;
    out.color = in.color;
    return out;
}

fragment float4 fragmentShader_Quadratic(VertexOut in [[stage_in]]) {
    float u = in.uv.x;
    float v = in.uv.y;
    float f = u * u - v;
    
    // Calculate gradient
    float2 duv = float2(dfdx(u), dfdy(v));
    float gradient = length(duv);
    
    // Calculate signed distance
    float distance = f / gradient;
    
    // Discard outside pixels
    if (distance * in.sign >= 0.0) {
//        discard_fragment();
        return float4(in.color.rgb, 0.1); // for viz
    }
    
    // Anti-aliasing smoothing
    float alpha = smoothstep(0, -1 * in.sign, distance);
    
    return float4(in.color.rgb, alpha);
}
