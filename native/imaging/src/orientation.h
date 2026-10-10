#pragma once

#include "image.h"

namespace gremote {

// Returns the image transformed for EXIF orientation 1..8 (others = 1).
Image Orient(const Image& source, int orientation);

}  // namespace gremote
