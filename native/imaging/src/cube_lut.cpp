#include "cube_lut.h"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <string>
#include <thread>

#include "gremote_imaging.h"

namespace gremote {
namespace {

constexpr size_t kMaxCubeBytes = 16u * 1024u * 1024u;
// Real-world LUTs often overshoot [0, 1] by rounding noise.
constexpr float kRangeSlack = 0.01f;

bool ParseFloats(const char* text, int count, float* out) {
  const char* cursor = text;
  for (int i = 0; i < count; ++i) {
    char* end = nullptr;
    const float value = std::strtof(cursor, &end);
    if (end == cursor || !std::isfinite(value)) return false;
    out[i] = value;
    cursor = end;
  }
  while (*cursor == ' ' || *cursor == '\t' || *cursor == '\r') ++cursor;
  return *cursor == '\0';
}

bool StartsWith(const std::string& line, const char* keyword) {
  const size_t length = std::strlen(keyword);
  return line.compare(0, length, keyword) == 0 &&
         (line.size() == length || line[length] == ' ' || line[length] == '\t');
}

struct AxisSample {
  int index;
  float fraction;
};

void ApplyRows(uint8_t* pixels, int width, int row_begin, int row_end,
               size_t stride, int channels, const CubeLut& lut, float strength,
               const AxisSample (&axes)[3][256]) {
  const int n = lut.size;
  const float* table = lut.table.data();
  const size_t step_g = size_t(n) * 3;
  const size_t step_b = size_t(n) * n * 3;
  for (int y = row_begin; y < row_end; ++y) {
    uint8_t* p = pixels + size_t(y) * stride;
    for (int x = 0; x < width; ++x, p += channels) {
      const AxisSample& r = axes[0][p[0]];
      const AxisSample& g = axes[1][p[1]];
      const AxisSample& b = axes[2][p[2]];
      const float fr = r.fraction, fg = g.fraction, fb = b.fraction;
      const float* c000 =
          table + size_t(r.index) * 3 + g.index * step_g + b.index * step_b;
      const float* c100 = c000 + 3;
      const float* c010 = c000 + step_g;
      const float* c001 = c000 + step_b;
      const float* c110 = c100 + step_g;
      const float* c101 = c100 + step_b;
      const float* c011 = c010 + step_b;
      const float* c111 = c110 + step_b;
      const float *v1, *v2;
      float w0, w1, w2, w3;
      if (fr > fg) {
        if (fg > fb) {
          v1 = c100; v2 = c110; w0 = 1 - fr; w1 = fr - fg; w2 = fg - fb; w3 = fb;
        } else if (fr > fb) {
          v1 = c100; v2 = c101; w0 = 1 - fr; w1 = fr - fb; w2 = fb - fg; w3 = fg;
        } else {
          v1 = c001; v2 = c101; w0 = 1 - fb; w1 = fb - fr; w2 = fr - fg; w3 = fg;
        }
      } else {
        if (fb > fg) {
          v1 = c001; v2 = c011; w0 = 1 - fb; w1 = fb - fg; w2 = fg - fr; w3 = fr;
        } else if (fb > fr) {
          v1 = c010; v2 = c011; w0 = 1 - fg; w1 = fg - fb; w2 = fb - fr; w3 = fr;
        } else {
          v1 = c010; v2 = c110; w0 = 1 - fg; w1 = fg - fr; w2 = fr - fb; w3 = fb;
        }
      }
      for (int c = 0; c < 3; ++c) {
        const float mapped =
            w0 * c000[c] + w1 * v1[c] + w2 * v2[c] + w3 * c111[c];
        const float original = p[c] * (1.0f / 255.0f);
        const float mixed = original + (mapped - original) * strength;
        const float scaled = std::clamp(mixed, 0.0f, 1.0f) * 255.0f + 0.5f;
        p[c] = uint8_t(scaled);
      }
    }
  }
}

}  // namespace

int ParseCube(const uint8_t* data, size_t length, CubeLut* out) {
  if (data == nullptr || out == nullptr || length == 0 ||
      length > kMaxCubeBytes) {
    return GREMOTE_LUT_PARSE;
  }
  CubeLut lut;
  size_t expected = 0;
  size_t values = 0;
  size_t cursor = 0;
  std::string line;
  while (cursor < length) {
    size_t end = cursor;
    while (end < length && data[end] != '\n') ++end;
    line.assign(reinterpret_cast<const char*>(data + cursor), end - cursor);
    cursor = end + 1;
    const size_t first = line.find_first_not_of(" \t\r");
    if (first == std::string::npos) continue;
    line.erase(0, first);
    if (line[0] == '#') continue;
    if (StartsWith(line, "TITLE")) continue;
    if (StartsWith(line, "LUT_3D_SIZE")) {
      if (lut.size != 0 || values != 0) return GREMOTE_LUT_PARSE;
      float size = 0;
      if (!ParseFloats(line.c_str() + 11, 1, &size)) return GREMOTE_LUT_PARSE;
      if (size < 2 || size > 128 || std::floor(size) != size) {
        return GREMOTE_LUT_PARSE;
      }
      lut.size = int(size);
      expected = size_t(lut.size) * lut.size * lut.size;
      lut.table.resize(expected * 3);
      continue;
    }
    if (StartsWith(line, "DOMAIN_MIN")) {
      if (!ParseFloats(line.c_str() + 10, 3, lut.domain_min.data()))
        return GREMOTE_LUT_PARSE;
      continue;
    }
    if (StartsWith(line, "DOMAIN_MAX")) {
      if (!ParseFloats(line.c_str() + 10, 3, lut.domain_max.data()))
        return GREMOTE_LUT_PARSE;
      continue;
    }
    if (StartsWith(line, "LUT_3D_INPUT_RANGE")) {
      float range[2];
      if (!ParseFloats(line.c_str() + 18, 2, range)) return GREMOTE_LUT_PARSE;
      lut.domain_min.fill(range[0]);
      lut.domain_max.fill(range[1]);
      continue;
    }
    if (lut.size == 0 || values >= expected) return GREMOTE_LUT_PARSE;
    float rgb[3];
    if (!ParseFloats(line.c_str(), 3, rgb)) return GREMOTE_LUT_PARSE;
    for (int c = 0; c < 3; ++c) {
      if (rgb[c] < -kRangeSlack || rgb[c] > 1.0f + kRangeSlack)
        return GREMOTE_LUT_RANGE;
      lut.table[values * 3 + c] = std::clamp(rgb[c], 0.0f, 1.0f);
    }
    ++values;
  }
  if (lut.size == 0 || values != expected) return GREMOTE_LUT_PARSE;
  for (int c = 0; c < 3; ++c) {
    if (!(lut.domain_max[c] > lut.domain_min[c])) return GREMOTE_LUT_PARSE;
  }
  *out = std::move(lut);
  return GREMOTE_OK;
}

void ApplyLut(uint8_t* pixels, int width, int height, size_t stride,
              int channels, const CubeLut& lut, float strength) {
  if (pixels == nullptr || width <= 0 || height <= 0 || lut.size < 2) return;
  strength = std::clamp(strength, 0.0f, 1.0f);
  AxisSample axes[3][256];
  const float last = float(lut.size - 1);
  for (int c = 0; c < 3; ++c) {
    const float span = lut.domain_max[c] - lut.domain_min[c];
    for (int v = 0; v < 256; ++v) {
      const float normalized =
          std::clamp((v / 255.0f - lut.domain_min[c]) / span, 0.0f, 1.0f);
      const float position = normalized * last;
      const int index = std::min(int(position), lut.size - 2);
      axes[c][v] = {index, position - float(index)};
    }
  }
  const int64_t pixel_count = int64_t(width) * height;
  const unsigned hardware = std::max(1u, std::thread::hardware_concurrency());
  const int workers =
      pixel_count < 65536 ? 1 : int(std::min(4u, hardware));
  if (workers == 1) {
    ApplyRows(pixels, width, 0, height, stride, channels, lut, strength, axes);
    return;
  }
  std::vector<std::thread> threads;
  const int rows_per_worker = (height + workers - 1) / workers;
  for (int w = 0; w < workers; ++w) {
    const int begin = w * rows_per_worker;
    const int end = std::min(height, begin + rows_per_worker);
    if (begin >= end) break;
    threads.emplace_back([=, &lut, &axes] {
      ApplyRows(pixels, width, begin, end, stride, channels, lut, strength,
                axes);
    });
  }
  for (auto& thread : threads) thread.join();
}

}  // namespace gremote
