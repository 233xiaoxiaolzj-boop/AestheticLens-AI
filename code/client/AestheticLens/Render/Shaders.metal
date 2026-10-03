#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float4 position [[attribute(0)]];
    float2 texCoords [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoords;
};

// 顶点着色器：全屏四边形映射
vertex VertexOut passThroughVertex(uint vertexID [[vertex_id]]) {
    // 两个三角形覆盖整个屏幕NDC [-1, 1]
    const float4 positions[6] = {
        float4(-1.0, -1.0, 0.0, 1.0),
        float4( 1.0, -1.0, 0.0, 1.0),
        float4(-1.0,  1.0, 0.0, 1.0),
        float4(-1.0,  1.0, 0.0, 1.0),
        float4( 1.0, -1.0, 0.0, 1.0),
        float4( 1.0,  1.0, 0.0, 1.0)
    };
    
    // UV 纹理坐标 [0, 1]
    const float2 texCoords[6] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(0.0, 0.0),
        float2(1.0, 1.0),
        float2(1.0, 0.0)
    };
    
    VertexOut out;
    out.position = positions[vertexID];
    out.texCoords = texCoords[vertexID];
    return out;
}

// 片元着色器：Metal MSL 512x512 3D LUT 片元着色
// 严格遵循 TDD v2.0.0 §3.2 规范与切片原点偏移项
fragment float4 lutFragmentShader(
    VertexOut in [[stage_in]],
    texture2d<float> cameraTexture [[texture(0)]],
    texture2d<float> lutTexture [[texture(1)]],
    constant float &intensity [[buffer(0)]]
) {
    constexpr sampler linearSampler(coord::normalized, filter::linear, address::clamp_to_edge);
    
    // 1. 采样相机原始帧像素 (BGRA 或 RGBA)
    float4 rawColor = cameraTexture.sample(linearSampler, in.texCoords);
    float3 rgb = clamp(rawColor.rgb, 0.0, 1.0);
    
    // 2. 64x64x64 3D LUT 切片索引推导
    float blueSlice = rgb.b * 63.0;
    
    float sliceLower = floor(blueSlice);
    float sliceUpper = min(sliceLower + 1.0, 63.0);
    float blueWeight = blueSlice - sliceLower;
    
    // 3. 计算 8x8 切片二维行列号 (Row, Col)
    float colLower = fmod(sliceLower, 8.0);
    float rowLower = floor(sliceLower / 8.0);
    
    float colUpper = fmod(sliceUpper, 8.0);
    float rowUpper = floor(sliceUpper / 8.0);
    
    // 4. 切片内归一化 UV 计算 (加 0.5 半像素中心偏移，避免边缘锯齿溢出)
    float2 uvLower = float2(
        (colLower * 64.0 + 0.5 + rgb.r * 63.0) / 512.0,
        (rowLower * 64.0 + 0.5 + rgb.g * 63.0) / 512.0
    );
    
    float2 uvUpper = float2(
        (colUpper * 64.0 + 0.5 + rgb.r * 63.0) / 512.0,
        (rowUpper * 64.0 + 0.5 + rgb.g * 63.0) / 512.0
    );
    
    // 5. 两次双线性采样与切片间线性插值
    float3 colorLower = lutTexture.sample(linearSampler, uvLower).rgb;
    float3 colorUpper = lutTexture.sample(linearSampler, uvUpper).rgb;
    float3 gradedRGB = mix(colorLower, colorUpper, blueWeight);
    
    // 6. 根据 intensity 与原图进行干湿比平滑混合
    float3 finalRGB = mix(rgb, gradedRGB, intensity);
    return float4(finalRGB, rawColor.a);
}
