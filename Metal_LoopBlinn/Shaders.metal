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
};

// Vertex output
struct VertexOut {
    float4 position [[position]];
    float2 uv;
    float sign;
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
    return out;
}

// Fragment shader (with anti-aliasing)
fragment float4 fragmentShader_Quadratic(
    VertexOut in [[stage_in]]
) {
    // Calculate implicit equation
    float u = in.uv.x;
    float v = in.uv.y;
    float f = u * u - v;
    
    // Discard outside pixels
    if (f * in.sign >= 0) {
        discard_fragment();
    }
    
    // Anti-aliasing processing
    float2 duv = float2(dfdx(u), dfdy(v));
    float gradient = length(duv);
    float distance = f / gradient;
    float alpha = smoothstep(0.5, -0.5, distance); // Smooth transition
    
    return float4(1.0, 0.0, 0.0, alpha); // Red with anti-aliasing
}