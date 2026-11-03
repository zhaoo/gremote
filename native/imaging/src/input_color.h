#pragma once
#include "image.h"
#include <vector>
namespace gremote {
// Empty means untagged. Malformed/reordered/incomplete ICC chunks are rejected.
bool ReadJpegIcc(const uint8_t* jpeg,size_t length,std::vector<uint8_t>* profile);
bool NormalizeToSrgb(Image* rgb,const std::vector<uint8_t>& icc,bool adobe_rgb);
}
