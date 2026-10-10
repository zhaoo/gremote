#include "resize.h"

#include <algorithm>
#include <cmath>

namespace gremote {
namespace {

struct Contribution {
  int first;
  std::vector<float> weights;  // normalized to sum 1
};

std::vector<Contribution> Contributions(int source, int target) {
  std::vector<Contribution> result(target);
  const double scale = double(source) / target;
  for (int i = 0; i < target; ++i) {
    const double begin = i * scale, end = (i + 1) * scale;
    const int first = int(std::floor(begin));
    const int last = std::min(source - 1, int(std::ceil(end)) - 1);
    result[i].first = first;
    for (int j = first; j <= last; ++j) {
      const double overlap =
          std::min(end, double(j + 1)) - std::max(begin, double(j));
      result[i].weights.push_back(float(overlap / scale));
    }
  }
  return result;
}

}  // namespace

Image ResizeArea(const Image& source, int width, int height) {
  width = std::min(width, source.width);
  height = std::min(height, source.height);
  if (width <= 0 || height <= 0 ||
      (width == source.width && height == source.height)) {
    return source;
  }
  const int c = source.channels;
  const auto columns = Contributions(source.width, width);
  const auto rows = Contributions(source.height, height);
  Image out(width, height, c);
  std::vector<float> horizontal(size_t(width) * c);
  std::vector<float> accumulator(size_t(width) * c);
  for (int y = 0; y < height; ++y) {
    std::fill(accumulator.begin(), accumulator.end(), 0.0f);
    const auto& row = rows[y];
    for (size_t k = 0; k < row.weights.size(); ++k) {
      const uint8_t* src = source.Row(row.first + int(k));
      for (int x = 0; x < width; ++x) {
        const auto& column = columns[x];
        for (int ch = 0; ch < c; ++ch) {
          float sum = 0;
          for (size_t m = 0; m < column.weights.size(); ++m) {
            sum += column.weights[m] * src[(column.first + m) * c + ch];
          }
          horizontal[size_t(x) * c + ch] = sum;
        }
      }
      const float weight = row.weights[k];
      for (size_t i = 0; i < accumulator.size(); ++i) {
        accumulator[i] += weight * horizontal[i];
      }
    }
    uint8_t* dst = out.Row(y);
    for (size_t i = 0; i < accumulator.size(); ++i) {
      dst[i] = uint8_t(std::clamp(accumulator[i] + 0.5f, 0.0f, 255.0f));
    }
  }
  return out;
}

}  // namespace gremote
