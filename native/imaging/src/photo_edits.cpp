#include "photo_edits.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <utility>
#include <vector>

#include "gremote_imaging.h"
#include "orientation.h"
#include "resize.h"

namespace gremote {
namespace {
constexpr float kPi = 3.14159265358979323846f;
float Clamp(float x) { return std::clamp(x, 0.f, 1.f); }
uint8_t Byte(float x) { return uint8_t(std::lround(Clamp(x) * 255)); }
bool Cancelled(const volatile int32_t *cancel) { return cancel && *cancel; }
float Luma(float r, float g, float b) {
  return .2126f * r + .7152f * g + .0722f * b;
}
float Smooth(float edge0, float edge1, float x) {
  const float t = Clamp((x - edge0) / std::max(.00001f, edge1 - edge0));
  return t * t * (3 - 2 * t);
}
uint32_t Hash(uint32_t x) {
  x ^= x >> 16;
  x *= 0x7feb352du;
  x ^= x >> 15;
  x *= 0x846ca68bu;
  return x ^ (x >> 16);
}
float Noise(int x, int y, uint32_t seed) {
  return (Hash(uint32_t(x) * 0x1f123bb5u ^ uint32_t(y) * 0x5f356495u ^ seed) &
          0xffffff) /
         16777215.f;
}
float Grain(float x, float y, float cells, uint32_t seed) {
  const float px = x * cells, py = y * cells;
  const int ix = int(std::floor(px)), iy = int(std::floor(py));
  const float fx = px - ix, fy = py - iy;
  const float a = Noise(ix, iy, seed) * (1 - fx) + Noise(ix + 1, iy, seed) * fx;
  const float b =
      Noise(ix, iy + 1, seed) * (1 - fx) + Noise(ix + 1, iy + 1, seed) * fx;
  return (a * (1 - fy) + b * fy) * 2 - 1;
}
Image Geometry(const Image &source, const PhotoEdits &edits) {
  const auto &p = edits.values;
  const int orientation[] = {1, 6, 3, 8};
  Image image = Orient(source, orientation[int(p[34])]);
  if (p[35])
    image = Orient(image, 2);
  if (p[36])
    image = Orient(image, 4);
  if (p[37] != 0) {
    Image straight(image.width, image.height, image.channels);
    const float angle = p[37] * kPi / 180, c = std::cos(angle),
                s = std::sin(angle);
    // Inverse-map an enlarged rotation: every output corner stays inside the
    // input.
    const float zoom =
        std::max(std::abs(c) + std::abs(s) * image.height / image.width,
                 std::abs(c) + std::abs(s) * image.width / image.height);
    const float cx = (image.width - 1) * .5f, cy = (image.height - 1) * .5f;
    for (int y = 0; y < image.height; ++y)
      for (int x = 0; x < image.width; ++x) {
        const float dx = (x - cx) / zoom, dy = (y - cy) / zoom;
        const float sx =
            std::clamp(c * dx + s * dy + cx, 0.f, float(image.width - 1));
        const float sy =
            std::clamp(-s * dx + c * dy + cy, 0.f, float(image.height - 1));
        const int x0 = int(sx), y0 = int(sy),
                  x1 = std::min(x0 + 1, image.width - 1),
                  y1 = std::min(y0 + 1, image.height - 1);
        const float fx = sx - x0, fy = sy - y0;
        for (int ch = 0; ch < image.channels; ++ch) {
          const float top = image.Row(y0)[x0 * image.channels + ch] * (1 - fx) +
                            image.Row(y0)[x1 * image.channels + ch] * fx;
          const float bottom =
              image.Row(y1)[x0 * image.channels + ch] * (1 - fx) +
              image.Row(y1)[x1 * image.channels + ch] * fx;
          straight.Row(y)[x * image.channels + ch] =
              uint8_t(std::lround(top * (1 - fy) + bottom * fy));
        }
      }
    image = std::move(straight);
  }
  // Float32 geometry is also used by the Dart size calculation. Clamp after
  // rounding because very wide legal panoramas can exceed float32 integer
  // precision.
  const int w = std::clamp(int(std::lround(image.width * p[32])), 1,
                           image.width),
            h = std::clamp(int(std::lround(image.height * p[33])), 1,
                           image.height);
  const int left =
      std::clamp(int(std::lround(image.width * p[30])), 0, image.width - w);
  const int top =
      std::clamp(int(std::lround(image.height * p[31])), 0, image.height - h);
  if (w == image.width && h == image.height)
    return image;
  Image crop(w, h, image.channels);
  for (int y = 0; y < h; ++y)
    std::memcpy(crop.Row(y), image.Row(top + y) + left * image.channels,
                crop.Stride());
  return crop;
}
float Curve(const float *samples, float x) {
  const float at = Clamp(x) * 255;
  const int low = int(at);
  const int high = std::min(255, low + 1);
  return samples[low] + (samples[high] - samples[low]) * (at - low);
}
void Basic(Image *image, const PhotoEdits &edits) {
  const auto &p = edits.values;
  bool active = false;
  for (int i = 1; i <= 10; ++i)
    active |= p[i] != 0;
  if (!active)
    return;
  const float exposure = std::exp2(p[1]), contrast = std::exp2(p[2] * 1.5f);
  for (size_t i = 0; i < image->pixels.size(); i += image->channels) {
    float rgb[3];
    for (int c = 0; c < 3; ++c) {
      float x = Clamp(image->pixels[i + c] / 255.f * exposure);
      if (p[2] != 0)
        x = x <= .5f ? .5f * std::pow(2 * x, contrast)
                     : 1 - .5f * std::pow(2 * (1 - x), contrast);
      x = Clamp(x + p[3] * .8f * x * x * (1 - x));
      x = Clamp(x + p[4] * .8f * x * (1 - x) * (1 - x));
      if (p[5] != 0)
        x = std::pow(x, std::exp2(-p[5] * .5f));
      x = Clamp(x + p[6] * .2f * (1 - x) * (1 - x));
      rgb[c] = x;
    }
    rgb[0] *= 1 + p[7] * .18f + p[8] * .08f;
    rgb[1] *= 1 - p[8] * .16f;
    rgb[2] *= 1 - p[7] * .18f + p[8] * .08f;
    const float luma = Luma(rgb[0], rgb[1], rgb[2]);
    const float chroma =
        *std::max_element(rgb, rgb + 3) - *std::min_element(rgb, rgb + 3);
    const float saturation = (1 + p[9]) * (1 + p[10] * (1 - Clamp(chroma)));
    for (int c = 0; c < 3; ++c)
      image->pixels[i + c] = Byte(luma + (rgb[c] - luma) * saturation);
  }
}
void Curves(Image *image, const PhotoEdits &edits) {
  const auto &p = edits.values;
  bool active = false;
  for (int c = 0; c < 4 && !active; ++c)
    for (int i = 0; i < 256; ++i)
      if (std::abs(p[38 + c * 256 + i] - i / 255.f) > 1e-7f) {
        active = true;
        break;
      }
  if (!active)
    return;
  for (size_t i = 0; i < image->pixels.size(); i += image->channels)
    for (int c = 0; c < 3; ++c)
      image->pixels[i + c] = Byte(Curve(
          &p[38 + (c + 1) * 256], Curve(&p[38], image->pixels[i + c] / 255.f)));
}
// Sliding-window separable boxes approximate a Gaussian in O(pixels),
// regardless of radius. Only scalar highlight masks are buffered, never large
// 2-D kernels.
void Blur(std::vector<float> *mask, int w, int h, int radius) {
  std::vector<float> temp(mask->size());
  for (int pass = 0; pass < 3; ++pass) {
    const int r = std::max(1, radius), span = 2 * r + 1;
    for (int y = 0; y < h; ++y) {
      double sum = (*mask)[y * w] * double(r + 1) +
                   (*mask)[y * w + w - 1] * double(std::max(0, r - w + 1));
      for (int k = 1; k <= std::min(r, w - 1); ++k)
        sum += (*mask)[y * w + k];
      for (int x = 0; x < w; ++x) {
        temp[y * w + x] = float(sum / span);
        sum += (*mask)[y * w + std::min(w - 1, x + r + 1)] -
               (*mask)[y * w + std::max(0, x - r)];
      }
    }
    for (int x = 0; x < w; ++x) {
      double sum = temp[x] * double(r + 1) +
                   temp[(h - 1) * w + x] * double(std::max(0, r - h + 1));
      for (int k = 1; k <= std::min(r, h - 1); ++k)
        sum += temp[k * w + x];
      for (int y = 0; y < h; ++y) {
        (*mask)[y * w + x] = float(sum / span);
        sum += temp[std::min(h - 1, y + r + 1) * w + x] -
               temp[std::max(0, y - r) * w + x];
      }
    }
  }
}
int Glow(Image *image, const PhotoEdits &edits, bool halation,
         const volatile int32_t *cancel) {
  const auto &p = edits.values;
  const int index = halation ? 17 : 20;
  if (p[index] == 0)
    return GREMOTE_OK;
  const int w = image->width, h = image->height, c = image->channels;
  std::vector<float> mask(size_t(w) * h);
  for (size_t i = 0; i < mask.size(); ++i) {
    const auto *rgb = &image->pixels[i * c];
    mask[i] = Smooth(p[index + 2], 1.f, Luma(rgb[0], rgb[1], rgb[2]) / 255.f);
  }
  const int radius = std::max(
      1, int(std::lround(std::max(w, h) * (.002f + .06f * p[index + 1]))));
  Blur(&mask, w, h, radius);
  if (Cancelled(cancel))
    return GREMOTE_CANCELLED;
  for (size_t i = 0; i < mask.size(); ++i)
    for (int channel = 0; channel < 3; ++channel) {
      const float color =
          halation ? (channel == 0 ? 1.f : (channel == 1 ? .25f : .08f)) : 1.f;
      const float value = image->pixels[i * c + channel] / 255.f;
      image->pixels[i * c + channel] =
          Byte(value + (1 - value) * mask[i] * p[index] * color * .8f);
    }
  return GREMOTE_OK;
}
void Texture(Image *image, const PhotoEdits &edits) {
  const auto &p = edits.values;
  if (p[11] == 0 && p[14] == 0 && p[23] == 0 && p[27] == 0 && p[28] == 0)
    return;
  const uint32_t seed = uint32_t(p[29]);
  const float jitter = (Noise(5, 11, seed) - .5f) * .2f;
  const float position = (p[24] + jitter) * 2 * kPi;
  const float leakx = .5f + .65f * std::cos(position),
              leaky = .5f + .65f * std::sin(position);
  float leakrgb[3];
  for (int c = 0; c < 3; ++c)
    leakrgb[c] = Clamp(.5f + .8f * std::cos(2 * kPi * (p[26] - c / 3.f)));
  const float cells = 45.f + 750.f * (1 - p[15]) * (1 - p[15]);
  const float size = .12f + p[12] * .9f, feather = .04f + p[13] * .9f;
  for (int y = 0; y < image->height; ++y)
    for (int x = 0; x < image->width; ++x) {
      const float nx = (x + .5f) / image->width, ny = (y + .5f) / image->height;
      const float dx = (nx - .5f) * 1.41421356f, dy = (ny - .5f) * 1.41421356f;
      const float vignette =
          1 - p[11] * Smooth(size * (1 - feather), size + feather * .5f,
                             std::sqrt(dx * dx + dy * dy));
      const float lx = nx - leakx, ly = ny - leaky;
      const float spread = .06f + p[25] * .75f;
      const float leak =
          p[23] * std::exp(-(lx * lx + ly * ly) / (2 * spread * spread));
      float grain = 0;
      if (p[14])
        grain = (Grain(nx, ny, cells, seed) * (1 - p[16] * .75f) +
                 Grain(nx, ny, cells * 3.7f, seed + 43) * p[16] * .75f) *
                p[14] * .22f;
      auto *px =
          &image->pixels[(size_t(y) * image->width + x) * image->channels];
      const float luma = Luma(px[0], px[1], px[2]) / 255.f;
      for (int c = 0; c < 3; ++c) {
        float value = (px[c] / 255.f * (1 - p[28]) + luma * p[28]) * vignette;
        value = value * (1 - p[27] * .35f) + p[27] * .13f;
        value += leak * leakrgb[c] * (1 - value);
        value += grain;
        px[c] = Byte(value);
      }
    }
}
} // namespace
PhotoEdits::PhotoEdits() {
  values[0] = 1;
  values[12] = .55f;
  values[13] = .72f;
  values[15] = .28f;
  values[16] = .4f;
  values[18] = .45f;
  values[19] = .65f;
  values[21] = .35f;
  values[22] = .6f;
  values[24] = .15f;
  values[25] = .55f;
  values[26] = .06f;
  values[29] = 7331;
  values[32] = values[33] = 1;
  for (int c = 0; c < 4; ++c)
    for (int i = 0; i < 256; ++i)
      values[38 + c * 256 + i] = i / 255.f;
}
int ParsePhotoEdits(const float *parameters, int count, PhotoEdits *out) {
  if (!parameters && count == 0) {
    *out = PhotoEdits();
    return GREMOTE_OK;
  }
  if (!parameters || count != kPhotoEditCount)
    return GREMOTE_INVALID_ARGUMENT;
  for (int i = 0; i < count; ++i)
    if (!std::isfinite(parameters[i]))
      return GREMOTE_INVALID_ARGUMENT;
  const auto *p = parameters;
  if (p[0] != 1 || p[1] < -3 || p[1] > 3)
    return GREMOTE_INVALID_ARGUMENT;
  for (int i = 2; i <= 10; ++i)
    if (p[i] < -1 || p[i] > 1)
      return GREMOTE_INVALID_ARGUMENT;
  if (p[11] < -1 || p[11] > 1)
    return GREMOTE_INVALID_ARGUMENT;
  for (int i = 12; i <= 28; ++i)
    if (p[i] < 0 || p[i] > 1)
      return GREMOTE_INVALID_ARGUMENT;
  if (p[29] < 1 || p[29] > 16777215 || p[29] != std::floor(p[29]))
    return GREMOTE_INVALID_ARGUMENT;
  for (int i = 30; i <= 33; ++i)
    if (p[i] < 0 || p[i] > 1)
      return GREMOTE_INVALID_ARGUMENT;
  if (p[32] <= 0 || p[33] <= 0 || p[30] + p[32] > 1.000001f ||
      p[31] + p[33] > 1.000001f)
    return GREMOTE_INVALID_ARGUMENT;
  if (p[34] < 0 || p[34] > 3 || p[34] != std::floor(p[34]) ||
      (p[35] != 0 && p[35] != 1) || (p[36] != 0 && p[36] != 1) || p[37] < -45 ||
      p[37] > 45)
    return GREMOTE_INVALID_ARGUMENT;
  for (int c = 0; c < 4; ++c)
    for (int i = 0; i < 256; ++i) {
      const int index = 38 + c * 256 + i;
      if (p[index] < 0 || p[index] > 1)
        return GREMOTE_INVALID_ARGUMENT;
    }
  std::copy(parameters, parameters + count, out->values.begin());
  return GREMOTE_OK;
}
int RenderPhoto(const Image &source, const PhotoEdits &edits,
                const CubeLut *lut, float lut_strength, int width, int height,
                Image *out, const volatile int32_t *cancel) {
  if (source.width <= 0 || source.height <= 0 ||
      (source.channels != 3 && source.channels != 4) || width <= 0 ||
      height <= 0 || !std::isfinite(lut_strength) || lut_strength < 0 ||
      lut_strength > 1)
    return GREMOTE_INVALID_ARGUMENT;
  if (int64_t(source.width) * source.height > kMaxPixels ||
      int64_t(width) * height > kMaxPixels)
    return GREMOTE_TOO_LARGE;
  if (Cancelled(cancel))
    return GREMOTE_CANCELLED;
  Image photo = Geometry(source, edits);
  if (width > photo.width || height > photo.height)
    return GREMOTE_INVALID_ARGUMENT;
  photo = ResizeArea(photo, width, height);
  if (Cancelled(cancel))
    return GREMOTE_CANCELLED;
  Basic(&photo, edits);
  if (lut)
    ApplyLut(photo.pixels.data(), photo.width, photo.height, photo.Stride(),
             photo.channels, *lut, lut_strength);
  Curves(&photo, edits);
  if (Cancelled(cancel))
    return GREMOTE_CANCELLED;
  int status = Glow(&photo, edits, true, cancel);
  if (status != GREMOTE_OK)
    return status;
  status = Glow(&photo, edits, false, cancel);
  if (status != GREMOTE_OK)
    return status;
  Texture(&photo, edits);
  if (Cancelled(cancel))
    return GREMOTE_CANCELLED;
  *out = std::move(photo);
  return GREMOTE_OK;
}
} // namespace gremote
