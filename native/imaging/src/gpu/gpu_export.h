#pragma once
#include "frame_compositor.h"
#include <string>
namespace gremote::gpu {
struct ExportSpec {
  int photo_width=0,photo_height=0,photo_x=0,photo_y=0,canvas_width=0,canvas_height=0,quality=95;
  uint8_t background[3]={0,0,0};
  std::vector<Overlay> overlays;
  std::string path;
};
}
