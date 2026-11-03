#include "tone_v2.h"

#include <algorithm>
#include <cmath>

namespace gremote {
namespace {
float Decode(float x) {
  return x <= .04045f ? x / 12.92f : std::pow((x + .055f) / 1.055f, 2.4f);
}
float Encode(float x) {
  return x <= .0031308f ? x * 12.92f : 1.055f * std::pow(x, 1 / 2.4f) - .055f;
}
float Sigmoid(float x) { return 1 / (1 + std::exp(-x)); }
float Luma(const std::array<float,3>& rgb) {
  return .2126f * rgb[0] + .7152f * rgb[1] + .0722f * rgb[2];
}
}  // namespace

ToneV2 ToneV2::Build(const PhotoEdits& edits) {
  ToneV2 tone;
  for (int i = 0; i < 10; ++i) {
    tone.p_[i] = edits.values[i+1];
    tone.active_ |= tone.p_[i] != 0;
  }
  tone.exposure_ = std::exp2(tone.p_[0]);
  tone.contrast_ = std::exp2(tone.p_[1] * .8f);
  const float temperature = tone.p_[6], tint = tone.p_[7];
  tone.gains_ = {std::exp2(temperature*.35f + tint*.1f),
                std::exp2(-tint*.2f),
                std::exp2(-temperature*.35f + tint*.1f)};
  tone.peak_ = std::max(1.f, tone.Luminance(*std::max_element(tone.gains_.begin(), tone.gains_.end())));
  return tone;
}

float ToneV2::Luminance(float source) const {
  float y = source * exposure_;
  if (y > 1e-12f) {
    // Log-light contrast about scene middle gray, followed by smooth regional
    // EV adjustments. Each map has positive derivative at every legal setting.
    constexpr float pivot = -2.473931188f;  // log2(.18)
    float l = pivot + contrast_ * (std::log2(y) - pivot);
    l += p_[2] * .8f * Sigmoid((l + .5f) / .55f);
    l += p_[3] * 1.2f * (1 - Sigmoid((l + 3.5f) / .8f));
    l += p_[4] * .5f * Sigmoid((l + .08f) / .22f);
    y = std::exp2(l);
  }
  // Black endpoint is local to the toe and remains monotonic. Unlike global
  // gamma, it does not move the white endpoint or the whole midtone range.
  if (p_[5] >= 0) y += p_[5] * .02f * std::exp(-y / .06f);
  else y += p_[5] * .015f * (-std::expm1(-y / .03f)) * std::exp(-y / .15f);
  return std::max(0.f, y);
}

float ToneV2::Shoulder(float y) const {
  constexpr float knee = .75f;
  if (peak_ <= 1 || y <= knee) return y;
  // Rational shoulder: slope 1 at the knee, maps the theoretical peak to 1.
  // When peak == 1 it is identity, so neutral content receives no default look.
  const float d = y - knee;
  return knee + d / (1 + d * (peak_ - 1) / ((peak_ - knee) * (1 - knee)));
}

std::array<float,3> ToneV2::Apply(std::array<float,3> encoded) const {
  if (!active_) return encoded;
  std::array<float,3> rgb;
  for (int c = 0; c < 3; ++c) rgb[c] = Decode(encoded[c]) * gains_[c];
  const float original = Luma(rgb);
  const float y = std::clamp(Shoulder(Luminance(original)), 0.f, 1.f);
  const float maximum = *std::max_element(rgb.begin(), rgb.end());
  const float minimum = *std::min_element(rgb.begin(), rgb.end());
  const float chroma = maximum > 1e-9f ? (maximum - minimum) / maximum : 0;
  const float saturation = (1+p_[8]) * (1+p_[9]*(1-chroma));
  std::array<float,3> delta;
  float gamut = 1;
  for (int c = 0; c < 3; ++c) {
    delta[c] = original > 1e-12f ? (rgb[c] * y / original - y) * saturation : 0;
    if (delta[c] > 1e-9f) gamut = std::min(gamut, (1-y)/delta[c]);
    if (delta[c] < -1e-9f) gamut = std::min(gamut, -y/delta[c]);
  }
  // Compress chroma about luminance instead of clipping each channel's hue.
  for (int c = 0; c < 3; ++c) rgb[c] = Encode(std::clamp(y + gamut*delta[c], 0.f, 1.f));
  return rgb;
}
}  // namespace gremote
