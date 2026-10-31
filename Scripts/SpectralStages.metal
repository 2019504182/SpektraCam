// Verified-stage acceleration experiment. Andrea Volpato / contributors, GPLv3.
#include <metal_stdlib>
using namespace metal;

kernel void density_curves(device const float4 *input [[buffer(0)]],
                           device const float *axis [[buffer(1)]],
                           device const float4 *curves [[buffer(2)]],
                           device float4 *output [[buffer(3)]],
                           constant uint2 &shape [[buffer(4)]],
                           uint pixel [[thread_position_in_grid]]) {
    if (pixel >= shape.x) return;
    float3 result;
    for (uint channel = 0; channel < 3; ++channel) {
        float x = input[pixel][channel];
        if (isnan(x)) { result[channel] = x; continue; }
        uint last = shape.y - 1;
        if (x <= axis[0]) { result[channel] = curves[0][channel]; continue; }
        if (x >= axis[last]) { result[channel] = curves[last][channel]; continue; }
        uint low = 0, high = shape.y;
        while (low < high) {
            uint middle = (low + high) / 2;
            if (axis[middle] <= x) low = middle + 1;
            else high = middle;
        }
        uint i = low - 1;
        float dx = axis[i + 1] - axis[i];
        float t = dx == 0 ? 0 : (x - axis[i]) / dx;
        result[channel] = curves[i][channel] + t * (curves[i + 1][channel] - curves[i][channel]);
    }
    output[pixel] = float4(result, 1);
}

struct SpectralSample {
    float4 channels_and_base;
    float4 normalized_illuminant_xyz;
};
kernel void spectral_xyz(device const float4 *input [[buffer(0)]],
                         device const SpectralSample *basis [[buffer(1)]],
                         device float4 *output [[buffer(2)]],
                         constant uint2 &shape [[buffer(3)]],
                         uint pixel [[thread_position_in_grid]]) {
    if (pixel >= shape.x) return;
    float3 xyz = float3(0);
    for (uint wavelength = 0; wavelength < shape.y; ++wavelength) {
        SpectralSample sample = basis[wavelength];
        float density = dot(input[pixel].xyz, sample.channels_and_base.xyz) + sample.channels_and_base.w;
        // Missing source spectral measurements become zero transmitted light upstream.
        float light = isnan(density) ? 0 : pow(10.0f, -density);
        xyz += light * sample.normalized_illuminant_xyz.xyz;
    }
    output[pixel] = float4(xyz, 1);
}
