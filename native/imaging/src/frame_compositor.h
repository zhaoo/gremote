#pragma once

#include <cstdint>
#include <vector>

#include "image.h"

namespace gremote {

struct Overlay {
  int x = 0;
  int y = 0;
  int width = 0;
  int height = 0;
  const uint8_t* rgba = nullptr;  // straight alpha
};

struct FrameSpec {
  int canvas_width = 0;
  int canvas_height = 0;
  uint8_t background[3] = {0, 0, 0};
  const Image* photo = nullptr;  // RGB8
  int photo_x = 0;
  int photo_y = 0;
  std::vector<Overlay> overlays;
};

int ValidateFrame(const FrameSpec& spec);

// Writes one RGB8 canvas row; spec must have passed ValidateFrame.
void ComposeRow(const FrameSpec& spec, int y, uint8_t* out_rgb);

}  // namespace gremote
