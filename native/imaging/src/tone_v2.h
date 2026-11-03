#pragma once

#include <array>
#include "photo_edits.h"

namespace gremote {
// Normalized SDR sRGB in/out. ICC conversion is the decoder's responsibility.
// Intermediate linear values retain headroom; the output boundary is explicit.
class ToneV2 {
 public:
  static ToneV2 Build(const PhotoEdits& edits);
  std::array<float, 3> Apply(std::array<float, 3> encoded) const;
  bool active() const { return active_; }

 private:
  float Luminance(float source) const;
  float Shoulder(float value) const;
  std::array<float, 10> p_{};
  std::array<float, 3> gains_{1,1,1};
  float exposure_ = 1, contrast_ = 1, peak_ = 1;
  bool active_ = false;
};
}  // namespace gremote
