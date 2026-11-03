#pragma once

#include "cube_lut.h"
#include "image.h"
#include <array>

namespace gremote {
constexpr int kPhotoEditCount = 1062;
struct PhotoEdits {
  std::array<float, kPhotoEditCount> values{};
  PhotoEdits();
};
// Null/count zero is the legacy identity recipe. All other inputs are strict
// v1/v2; unknown future versions are rejected.
int ParsePhotoEdits(const float *parameters, int count, PhotoEdits *out);
// Source is already EXIF-oriented. Both C preview and JPEG export use this
// core.
int RenderPhoto(const Image &source, const PhotoEdits &edits,
                const CubeLut *lut, float lut_strength, int width, int height,
                Image *out, const volatile int32_t *cancel = nullptr);
} // namespace gremote
