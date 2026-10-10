#pragma once

#include "image.h"

namespace gremote {

// Area-average down-scaling. Targets at or above the source size return a
// copy: the core never upscales.
Image ResizeArea(const Image& source, int width, int height);

}  // namespace gremote
