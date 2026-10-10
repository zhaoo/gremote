#include "frame_compositor.h"

#include <algorithm>
#include <cstring>

#include "gremote_imaging.h"

namespace gremote {
namespace {

bool Inside(int x, int y, int w, int h, int canvas_w, int canvas_h) {
  return w > 0 && h > 0 && x >= 0 && y >= 0 && int64_t(x) + w <= canvas_w &&
         int64_t(y) + h <= canvas_h;
}

}  // namespace

int ValidateFrame(const FrameSpec& spec) {
  if (spec.canvas_width <= 0 || spec.canvas_height <= 0 ||
      spec.photo == nullptr || spec.photo->channels != 3 ||
      !Inside(spec.photo_x, spec.photo_y, spec.photo->width,
              spec.photo->height, spec.canvas_width, spec.canvas_height)) {
    return GREMOTE_INVALID_ARGUMENT;
  }
  for (const auto& overlay : spec.overlays) {
    if (overlay.rgba == nullptr ||
        !Inside(overlay.x, overlay.y, overlay.width, overlay.height,
                spec.canvas_width, spec.canvas_height)) {
      return GREMOTE_INVALID_ARGUMENT;
    }
  }
  return GREMOTE_OK;
}

void ComposeRow(const FrameSpec& spec, int y, uint8_t* out) {
  for (int x = 0; x < spec.canvas_width; ++x) {
    std::memcpy(out + size_t(x) * 3, spec.background, 3);
  }
  const Image& photo = *spec.photo;
  if (y >= spec.photo_y && y < spec.photo_y + photo.height) {
    std::memcpy(out + size_t(spec.photo_x) * 3, photo.Row(y - spec.photo_y),
                photo.Stride());
  }
  for (const auto& overlay : spec.overlays) {
    if (y < overlay.y || y >= overlay.y + overlay.height) continue;
    const uint8_t* src = overlay.rgba + size_t(y - overlay.y) * overlay.width * 4;
    uint8_t* dst = out + size_t(overlay.x) * 3;
    for (int x = 0; x < overlay.width; ++x, src += 4, dst += 3) {
      const int alpha = src[3];
      if (alpha == 0) continue;
      for (int c = 0; c < 3; ++c) {
        dst[c] = uint8_t((src[c] * alpha + dst[c] * (255 - alpha) + 127) / 255);
      }
    }
  }
}

}  // namespace gremote
