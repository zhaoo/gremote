#pragma once

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

#include "image.h"

namespace gremote_test {

inline gremote::Image Gradient(int width, int height) {
  gremote::Image image(width, height, 3);
  for (int y = 0; y < height; ++y) {
    for (int x = 0; x < width; ++x) {
      uint8_t* p = image.Row(y) + x * 3;
      p[0] = uint8_t(x * 255 / (width > 1 ? width - 1 : 1));
      p[1] = uint8_t(y * 255 / (height > 1 ? height - 1 : 1));
      p[2] = 96;
    }
  }
  return image;
}

inline std::string TempPath(const std::string& name) {
  const char* dir = std::getenv("TMPDIR");
  std::string base = dir && *dir ? dir : "/tmp";
  if (base.back() != '/') base += '/';
  return base + "gremote-" + std::to_string(getpid()) + "-" + name;
}

inline std::vector<uint8_t> ReadFile(const std::string& path) {
  std::ifstream in(path, std::ios::binary);
  return std::vector<uint8_t>(std::istreambuf_iterator<char>(in), {});
}

inline bool FileExists(const std::string& path) {
  struct stat info;
  return stat(path.c_str(), &info) == 0;
}

inline bool FdIsClosed(int fd) { return fcntl(fd, F_GETFD) == -1; }

inline double MeanAbsDiff(const gremote::Image& a, const gremote::Image& b) {
  if (a.pixels.size() != b.pixels.size()) return 1e9;
  double sum = 0;
  for (size_t i = 0; i < a.pixels.size(); ++i) {
    sum += std::abs(int(a.pixels[i]) - int(b.pixels[i]));
  }
  return sum / a.pixels.size();
}

// Rewrites the frame size in the first SOF0/SOF2 marker.
inline bool PatchSofSize(std::vector<uint8_t>* bytes, int width, int height) {
  for (size_t i = 2; i + 9 < bytes->size(); ++i) {
    if ((*bytes)[i] == 0xFF &&
        ((*bytes)[i + 1] == 0xC0 || (*bytes)[i + 1] == 0xC2)) {
      (*bytes)[i + 5] = uint8_t(height >> 8);
      (*bytes)[i + 6] = uint8_t(height & 0xff);
      (*bytes)[i + 7] = uint8_t(width >> 8);
      (*bytes)[i + 8] = uint8_t(width & 0xff);
      return true;
    }
  }
  return false;
}

}  // namespace gremote_test
