#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// The halftone sky, one pixel at a time (Sky.swift has the why). Positions are in points.
constant float cell = 6.0;
constant float radius = cell * 0.62;

static float ink(float2 c, float2 size, float2 clear, float progress, device const float *lift, int bars, float3 tabs, bool isPeach) {
    float u = c.x / size.x, v = c.y / size.y;
    // The design's curves had blue gone at 0.413 and the horizon at 0.56 of the height; each is stretched to its own side of the clear band.
    float vb = v * 0.413 * size.y / max(clear.x, 1.0), vp = 0.56 + 0.44 * (c.y - clear.y) / max(size.y - clear.y, 1.0);
    float horizon = 0.56 - 0.08 * progress - lift[clamp(int(u * bars), 0, bars - 1)];
    float peach = saturate((vp - horizon) * 1.45), blue = saturate(0.62 - vb * 1.5 - 0.048 * progress);
    for (int n = 0; n < 3; n++) {
        float age = tabs[n];
        if (age < 0) continue;
        // A warm wave from the bottom up, about a second.
        float swell = exp(-age * 2.2) * min(age * 5, 1.0), front = saturate((v - (1 - age * 2)) * 3 + 1);
        peach += 0.32 * swell * saturate(v * 1.6) * front;
        blue -= 0.12 * swell;
    }
    // Typing and Tabs lift the peach; it may move into the margin but fades out halfway, short of the content. Blue only ever recedes.
    peach *= saturate((c.y - clear.y + 24) / 24);
    return saturate(isPeach ? peach : blue);
}

// How much of the nearest dots covers p: dot area is ink, so the radius goes with the square root.
static float cover(float2 p, float2 offset, float2 size, float2 clear, float progress, device const float *lift, int bars, float3 tabs, bool isPeach) {
    float2 base = floor((p - offset) / cell);
    float best = 0;
    for (int j = 0; j <= 1; j++) for (int i = 0; i <= 1; i++) {
        float2 c = (base + float2(i, j)) * cell + offset;
        float d = ink(c, size, clear, progress, lift, bars, tabs, isPeach);
        if (d < 0.04) continue;
        best = max(best, saturate(radius * sqrt(d) - distance(p, c) + 0.5));
    }
    return best;
}

[[ stitchable ]] half4 sky(float2 p, half4 color, float2 size, float2 clear, float progress, device const float *lift, int bars, float3 tabs,
                           half4 paper, half4 blue, half4 peach, float dark) {
    float b = cover(p, float2(0), size, clear, progress, lift, bars, tabs, false);
    float a = cover(p, float2(cell / 2), size, clear, progress, lift, bars, tabs, true);
    // Inks on paper multiply; on a dark window they add, like light.
    half3 out = dark > 0.5 ? paper.rgb + blue.rgb * b + peach.rgb * a
                           : paper.rgb * mix(half3(1), blue.rgb, half(b)) * mix(half3(1), peach.rgb, half(a));
    return half4(out, 1);
}
