#include "orientation.h"

#include <cstring>

namespace gremote {

Image Orient(const Image& source, int orientation) {
  if (orientation < 2 || orientation > 8) return source;
  const int w = source.width, h = source.height, c = source.channels;
  const bool swap = orientation >= 5;
  Image out(swap ? h : w, swap ? w : h, c);
  for (int y = 0; y < out.height; ++y) {
    uint8_t* row = out.Row(y);
    for (int x = 0; x < out.width; ++x) {
      int sx = x, sy = y;
      switch (orientation) {
        case 2: sx = w - 1 - x; break;
        case 3: sx = w - 1 - x; sy = h - 1 - y; break;
        case 4: sy = h - 1 - y; break;
        case 5: sx = y; sy = x; break;
        case 6: sx = y; sy = h - 1 - x; break;
        case 7: sx = w - 1 - y; sy = h - 1 - x; break;
        case 8: sx = w - 1 - y; sy = x; break;
      }
      std::memcpy(row + size_t(x) * c, source.Row(sy) + size_t(sx) * c, c);
    }
  }
  return out;
}

}  // namespace gremote
