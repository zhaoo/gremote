#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace gremote {

struct CubeLut {
  int size = 0;
  std::array<float, 3> domain_min{0.f, 0.f, 0.f};
  std::array<float, 3> domain_max{1.f, 1.f, 1.f};
  // size^3 RGB triplets, red index varies fastest.
  std::vector<float> table;
};

// Returns an GREMOTE_* status code.
int ParseCube(const uint8_t* data, size_t length, CubeLut* out);

// Maps 8-bit RGB(A) pixels in place; channels is 3 or 4 and alpha is kept.
void ApplyLut(uint8_t* pixels, int width, int height, size_t stride,
              int channels, const CubeLut& lut, float strength);

}  // namespace gremote
