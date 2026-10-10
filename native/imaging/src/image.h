#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>

namespace gremote {

// Tightly packed 8-bit image.
struct Image {
  Image() = default;
  Image(int w, int h, int c)
      : width(w), height(h), channels(c),
        pixels(size_t(w) * size_t(h) * size_t(c)) {}

  uint8_t* Row(int y) { return pixels.data() + size_t(y) * Stride(); }
  const uint8_t* Row(int y) const {
    return pixels.data() + size_t(y) * Stride();
  }
  size_t Stride() const { return size_t(width) * size_t(channels); }

  int width = 0;
  int height = 0;
  int channels = 3;
  std::vector<uint8_t> pixels;
};

// Decoded images above this pixel count are rejected.
constexpr int64_t kMaxPixels = 100LL * 1000 * 1000;

}  // namespace gremote
