// Liquid glass refraction (a BackdropFilter shader; Impeller only).
//
// The engine fills uSize (the bound texture's size) and uTexture (the
// backdrop). The glass shape is a rounded rectangle given in the same
// pixel space as FlutterFragCoord(): near its edge the backdrop is sampled
// from further out along the edge's normal, so what sits just outside the
// glass bends into its rim, as a thick lens does. A faint colour split at
// the rim gives the edge its prismatic catch. Inside the band the image is
// left as it is (the blur under this filter already softened it).
#version 460 core

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform vec4 uRect;       // x, y, width, height of the glass, in texture pixels
uniform float uRadius;    // corner radius, texture pixels
uniform float uRefraction; // the largest pull at the very edge, texture pixels
uniform float uBand;      // how far in from the edge the bending reaches
uniform float uChroma;    // colour split at the rim, 0..1
uniform float uDebug;     // 1: paint the texture coordinates (development only)

uniform sampler2D uTexture;

out vec4 fragColor;

float roundRectDistance(vec2 p, vec2 halfSize, float r) {
  vec2 q = abs(p) - halfSize + r;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

vec4 sampleAt(vec2 coord) {
  return texture(uTexture, clamp(coord / uSize, vec2(0.0), vec2(1.0)));
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  if (uDebug > 0.5) {
    fragColor = vec4(frag / uSize, 0.0, 1.0);
    return;
  }
  vec2 halfSize = uRect.zw * 0.5;
  vec2 p = frag - (uRect.xy + halfSize);
  float r = min(uRadius, min(halfSize.x, halfSize.y));
  float d = roundRectDistance(p, halfSize, r);
  float depth = -d; // > 0 inside, 0 on the edge
  if (depth <= 0.0 || uRefraction <= 0.0 || uBand <= 0.0) {
    fragColor = sampleAt(frag);
    return;
  }
  // The edge's outward normal, from the distance field.
  vec2 e = vec2(1.0, 0.0);
  vec2 n = vec2(
    roundRectDistance(p + e.xy, halfSize, r) - roundRectDistance(p - e.xy, halfSize, r),
    roundRectDistance(p + e.yx, halfSize, r) - roundRectDistance(p - e.yx, halfSize, r));
  float len = length(n);
  n = len > 0.0001 ? n / len : vec2(0.0);
  float t = clamp(1.0 - depth / uBand, 0.0, 1.0);
  float bend = t * t * (3.0 - 2.0 * t); // smooth into the rim
  bend = bend * bend;
  vec2 pull = n * bend * uRefraction;
  if (uChroma > 0.0) {
    float split = 1.0 + uChroma * 0.35 * bend;
    float red = sampleAt(frag + pull * split).r;
    vec4 mid = sampleAt(frag + pull);
    float blue = sampleAt(frag + pull / split).b;
    fragColor = vec4(red, mid.g, blue, mid.a);
  } else {
    fragColor = sampleAt(frag + pull);
  }
}
