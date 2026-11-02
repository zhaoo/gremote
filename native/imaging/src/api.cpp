#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <algorithm>
#include <cerrno>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <new>
#include <string>
#include <vector>

#include "cube_lut.h"
#include "frame_compositor.h"
#include "gremote_imaging.h"
#include "image.h"
#include "jpeg_io.h"
#include "orientation.h"
#include "photo_edits.h"
#include "resize.h"

namespace {

constexpr int64_t kMaxSourceBytes = 200LL * 1024 * 1024;
constexpr int kCancelCheckRows = 64;

class FdGuard {
public:
  explicit FdGuard(int fd) : fd_(fd) {}
  ~FdGuard() { Close(); }
  void Close() {
    if (fd_ >= 0)
      close(fd_);
    fd_ = -1;
  }
  int fd() const { return fd_; }

private:
  int fd_;
};

int ReadAll(FdGuard *guard, std::vector<uint8_t> *out) {
  if (guard->fd() < 0)
    return GREMOTE_INVALID_ARGUMENT;
  struct stat info;
  if (fstat(guard->fd(), &info) == 0 && S_ISREG(info.st_mode)) {
    if (info.st_size > kMaxSourceBytes)
      return GREMOTE_TOO_LARGE;
    out->reserve(size_t(info.st_size));
  }
  uint8_t buffer[64 * 1024];
  while (true) {
    const ssize_t count = read(guard->fd(), buffer, sizeof(buffer));
    if (count < 0) {
      if (errno == EINTR)
        continue;
      return GREMOTE_IO;
    }
    if (count == 0)
      break;
    if (int64_t(out->size()) + count > kMaxSourceBytes)
      return GREMOTE_TOO_LARGE;
    out->insert(out->end(), buffer, buffer + count);
  }
  guard->Close();
  return GREMOTE_OK;
}

bool Cancelled(const volatile int32_t *cancel) {
  return cancel != nullptr && *cancel != 0;
}

int DecodeOriented(FdGuard *guard, int orientation, int max_edge,
                   gremote::Image *out) {
  std::vector<uint8_t> bytes;
  int status = ReadAll(guard, &bytes);
  if (status != GREMOTE_OK)
    return status;
  int width = 0, height = 0;
  status = gremote::ReadJpegSize(bytes.data(), bytes.size(), &width, &height);
  if (status != GREMOTE_OK)
    return status;
  const int denom =
      max_edge > 0 ? gremote::ChooseScaleDenom(width, height, max_edge) : 1;
  gremote::Image decoded;
  status = gremote::DecodeJpeg(bytes.data(), bytes.size(), denom, &decoded);
  if (status != GREMOTE_OK)
    return status;
  bytes.clear();
  bytes.shrink_to_fit();
  *out = gremote::Orient(decoded, orientation);
  return GREMOTE_OK;
}

int ParseOptionalCube(const uint8_t *cube, int64_t length,
                      gremote::CubeLut *lut, bool *present) {
  if (length < 0 || (cube == nullptr && length != 0))
    return GREMOTE_INVALID_ARGUMENT;
  *present = cube != nullptr && length > 0;
  if (!*present)
    return GREMOTE_OK;
  return gremote::ParseCube(cube, size_t(length), lut);
}

int Export(const gremote_export_request &request, FdGuard *guard,
           const volatile int32_t *cancel) {
  if (request.output_path == nullptr || request.photo_width <= 0 ||
      request.photo_height <= 0 || request.quality < 1 ||
      request.quality > 100 || request.overlay_count < 0 ||
      (request.overlay_count > 0 && request.overlays == nullptr)) {
    return GREMOTE_INVALID_ARGUMENT;
  }
  gremote::PhotoEdits edits;
  int edit_status =
      gremote::ParsePhotoEdits(request.edits, request.edit_count, &edits);
  if (edit_status != GREMOTE_OK || !std::isfinite(request.lut_strength) ||
      request.lut_strength < 0 || request.lut_strength > 1 ||
      request.orientation < 1 || request.orientation > 8)
    return GREMOTE_INVALID_ARGUMENT;
  gremote::CubeLut lut;
  bool has_lut = false;
  int status =
      ParseOptionalCube(request.cube, request.cube_length, &lut, &has_lut);
  if (status != GREMOTE_OK)
    return status;
  if (Cancelled(cancel))
    return GREMOTE_CANCELLED;

  gremote::Image photo;
  status = DecodeOriented(guard, request.orientation, 0, &photo);
  if (status != GREMOTE_OK)
    return status;
  if (Cancelled(cancel))
    return GREMOTE_CANCELLED;
  gremote::Image rendered;
  status = gremote::RenderPhoto(photo, edits, has_lut ? &lut : nullptr,
                                request.lut_strength, request.photo_width,
                                request.photo_height, &rendered, cancel);
  if (status != GREMOTE_OK)
    return status;
  photo = std::move(rendered);
  if (Cancelled(cancel))
    return GREMOTE_CANCELLED;

  gremote::FrameSpec spec;
  spec.canvas_width = request.canvas_width;
  spec.canvas_height = request.canvas_height;
  spec.background[0] = request.background_r;
  spec.background[1] = request.background_g;
  spec.background[2] = request.background_b;
  spec.photo = &photo;
  spec.photo_x = request.photo_x;
  spec.photo_y = request.photo_y;
  for (int i = 0; i < request.overlay_count; ++i) {
    const auto &o = request.overlays[i];
    spec.overlays.push_back({o.x, o.y, o.width, o.height, o.rgba});
  }
  status = gremote::ValidateFrame(spec);
  if (status != GREMOTE_OK)
    return status;

  gremote::JpegRowWriter writer;
  status = writer.Open(request.output_path, spec.canvas_width,
                       spec.canvas_height, request.quality);
  if (status != GREMOTE_OK)
    return status;
  std::vector<uint8_t> row(size_t(spec.canvas_width) * 3);
  for (int y = 0; y < spec.canvas_height; ++y) {
    if (y % kCancelCheckRows == 0 && Cancelled(cancel)) {
      writer.Abort();
      return GREMOTE_CANCELLED;
    }
    gremote::ComposeRow(spec, y, row.data());
    status = writer.WriteRow(row.data());
    if (status != GREMOTE_OK)
      return status;
  }
  return writer.Finish();
}

} // namespace

extern "C" {

int32_t gremote_decode_preview(int32_t fd, int32_t orientation,
                               int32_t max_edge, uint8_t **out_rgba,
                               int32_t *out_width, int32_t *out_height) {
  FdGuard guard(fd);
  if (max_edge <= 0 || out_rgba == nullptr || out_width == nullptr ||
      out_height == nullptr) {
    return GREMOTE_INVALID_ARGUMENT;
  }
  try {
    gremote::Image image;
    int status = DecodeOriented(&guard, orientation, max_edge, &image);
    if (status != GREMOTE_OK)
      return status;
    const int long_edge = std::max(image.width, image.height);
    if (long_edge > max_edge) {
      const double scale = double(max_edge) / long_edge;
      image = gremote::ResizeArea(
          image, std::max(1, int(std::lround(image.width * scale))),
          std::max(1, int(std::lround(image.height * scale))));
    }
    const size_t pixels = size_t(image.width) * image.height;
    auto *rgba = static_cast<uint8_t *>(std::malloc(pixels * 4));
    if (rgba == nullptr)
      return GREMOTE_OUT_OF_MEMORY;
    for (size_t i = 0; i < pixels; ++i) {
      std::memcpy(rgba + i * 4, image.pixels.data() + i * 3, 3);
      rgba[i * 4 + 3] = 255;
    }
    *out_rgba = rgba;
    *out_width = image.width;
    *out_height = image.height;
    return GREMOTE_OK;
  } catch (const std::bad_alloc &) {
    return GREMOTE_OUT_OF_MEMORY;
  }
}

int32_t gremote_lut_validate(const uint8_t *cube, int64_t length,
                             int32_t *out_size) {
  if (length < 0)
    return GREMOTE_INVALID_ARGUMENT;
  try {
    gremote::CubeLut lut;
    const int status = gremote::ParseCube(cube, size_t(length), &lut);
    if (status == GREMOTE_OK && out_size != nullptr)
      *out_size = lut.size;
    return status;
  } catch (const std::bad_alloc &) {
    return GREMOTE_OUT_OF_MEMORY;
  }
}

int32_t gremote_apply_lut_rgba(uint8_t *rgba, int32_t width, int32_t height,
                               const uint8_t *cube, int64_t length,
                               float strength) {
  if (rgba == nullptr || width <= 0 || height <= 0 || length < 0)
    return GREMOTE_INVALID_ARGUMENT;
  try {
    gremote::CubeLut lut;
    const int status = gremote::ParseCube(cube, size_t(length), &lut);
    if (status != GREMOTE_OK)
      return status;
    gremote::ApplyLut(rgba, width, height, size_t(width) * 4, 4, lut, strength);
    return GREMOTE_OK;
  } catch (const std::bad_alloc &) {
    return GREMOTE_OUT_OF_MEMORY;
  }
}

int32_t gremote_render_edit_rgba(const uint8_t *rgba, int32_t width,
                                 int32_t height, const float *parameters,
                                 int32_t edit_count, const uint8_t *cube,
                                 int64_t cube_length, float lut_strength,
                                 int32_t target_width, int32_t target_height,
                                 uint8_t **out_rgba) {
  if (out_rgba == nullptr)
    return GREMOTE_INVALID_ARGUMENT;
  *out_rgba = nullptr;
  if (rgba == nullptr || width <= 0 || height <= 0 || target_width <= 0 ||
      target_height <= 0 || !std::isfinite(lut_strength) || lut_strength < 0 ||
      lut_strength > 1)
    return GREMOTE_INVALID_ARGUMENT;
  if (int64_t(width) * height > gremote::kMaxPixels ||
      int64_t(target_width) * target_height > gremote::kMaxPixels)
    return GREMOTE_TOO_LARGE;
  try {
    gremote::PhotoEdits edits;
    int status = gremote::ParsePhotoEdits(parameters, edit_count, &edits);
    if (status != GREMOTE_OK)
      return status;
    gremote::CubeLut lut;
    bool present = false;
    status = ParseOptionalCube(cube, cube_length, &lut, &present);
    if (status != GREMOTE_OK)
      return status;
    gremote::Image source(width, height, 4), output;
    std::memcpy(source.pixels.data(), rgba, source.pixels.size());
    status = gremote::RenderPhoto(source, edits, present ? &lut : nullptr,
                                  lut_strength, target_width, target_height,
                                  &output);
    if (status != GREMOTE_OK)
      return status;
    auto *result = static_cast<uint8_t *>(std::malloc(output.pixels.size()));
    if (result == nullptr)
      return GREMOTE_OUT_OF_MEMORY;
    std::memcpy(result, output.pixels.data(), output.pixels.size());
    *out_rgba = result;
    return GREMOTE_OK;
  } catch (const std::bad_alloc &) {
    return GREMOTE_OUT_OF_MEMORY;
  }
}

int32_t gremote_export_jpeg(const gremote_export_request *request,
                            const volatile int32_t *cancel) {
  if (request == nullptr)
    return GREMOTE_INVALID_ARGUMENT;
  FdGuard guard(request->fd);
  try {
    return Export(*request, &guard, cancel);
  } catch (const std::bad_alloc &) {
    return GREMOTE_OUT_OF_MEMORY;
  }
}

void gremote_free(void *pointer) { std::free(pointer); }

} // extern "C"
