#include <metal_stdlib>
using namespace metal;

/// Compute kernel to calculate sum of squared differences for PSNR calculation
/// Each thread writes its squared difference to a buffer for CPU-side summation
kernel void calculateSquaredDifferences(
    texture2d<float, access::read> textureA [[texture(0)]],
    texture2d<float, access::read> textureB [[texture(1)]],
    device float *squaredDifferences [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Check if thread is within texture bounds
    if (gid.x < textureA.get_width() && gid.y < textureA.get_height()) {
        // Read pixels from both textures (values are in [0, 1] range)
        float4 pixelA = textureA.read(gid);
        float4 pixelB = textureB.read(gid);

        // Scale to [0, 255] range for PSNR calculation
        pixelA *= 255.0;
        pixelB *= 255.0;

        // Calculate squared difference for each channel (RGBA)
        float4 diff = pixelA - pixelB;
        float squared_diff = diff.r * diff.r + diff.g * diff.g + diff.b * diff.b + diff.a * diff.a;

        // Write to output buffer
        uint index = gid.y * textureA.get_width() + gid.x;
        squaredDifferences[index] = squared_diff;
    }
}
