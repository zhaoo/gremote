#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <limits>
#include <vector>

#include "gremote_imaging.h"
#include "test_main.h"

namespace {
using Edits = std::array<float, 1062>;
Edits Neutral() {
  Edits p{};
  p[0] = 1;
  p[12] = .5;
  p[13] = .5;
  p[15] = .4;
  p[16] = .5;
  p[18] = .3;
  p[19] = .65;
  p[21] = .4;
  p[22] = .6;
  p[25] = .5;
  p[29] = 7331;
  p[32] = p[33] = 1;
  for (int c = 0; c < 4; ++c)
    for (int i = 0; i < 256; ++i)
      p[38 + c * 256 + i] = i / 255.f;
  return p;
}
std::vector<uint8_t> Fixture(int w = 48, int h = 32) {
  std::vector<uint8_t> v(w * h * 4);
  for (int y = 0; y < h; ++y)
    for (int x = 0; x < w; ++x) {
      auto *px = &v[(y * w + x) * 4];
      px[0] = uint8_t(25 + x * 205 / (w - 1));
      px[1] = uint8_t(20 + y * 210 / (h - 1));
      px[2] = uint8_t(35 + (x + y) * 170 / (w + h - 2));
      px[3] = uint8_t((x * 7 + y * 3) % 256);
    }
  return v;
}
std::vector<uint8_t> Render(const std::vector<uint8_t> &src, const Edits &p,
                            int w = 48, int h = 32, int ow = 48, int oh = 32) {
  uint8_t *out = nullptr;
  EXPECT_EQ(gremote_render_edit_rgba(src.data(), w, h, p.data(), p.size(),
                                     nullptr, 0, 1, ow, oh, &out),
            GREMOTE_OK);
  if (!out)
    return {};
  std::vector<uint8_t> result(out, out + ow * oh * 4);
  gremote_free(out);
  return result;
}
double Diff(const std::vector<uint8_t> &a, const std::vector<uint8_t> &b) {
  if (a.size() != b.size() || a.empty())
    return 0;
  double d = 0;
  for (size_t i = 0; i < a.size(); ++i)
    if (i % 4 != 3)
      d += std::abs(int(a[i]) - b[i]);
  return d / (a.size() / 4 * 3);
}
} // namespace
TEST(PhotoEditsNeutralPreservesInputAndAlpha) {
  const auto src = Fixture();
  const auto before = src;
  auto out = Render(src, Neutral());
  EXPECT_TRUE(out == src);
  EXPECT_TRUE(src == before);
}
TEST(PhotoEditsAllBasicControlsAndCurvesAffectPixels) {
  const auto src = Fixture();
  for (int i = 1; i <= 10; ++i) {
    auto p = Neutral();
    p[i] = .65;
    auto out = Render(src, p);
    EXPECT_TRUE(Diff(out, src) > .3);
    if (out.size() == src.size())
      for (size_t j = 3; j < src.size(); j += 4)
        EXPECT_EQ(out[j], src[j]);
  }
  for (int c = 0; c < 4; ++c) {
    auto p = Neutral();
    for (int i = 0; i < 256; ++i)
      p[38 + c * 256 + i] = std::sqrt(i / 255.f);
    EXPECT_TRUE(Diff(Render(src, p), src) > 1);
  }
}
TEST(PhotoEditsToneControlsPreserveMonotonicRamps) {
  std::vector<uint8_t> ramp(256 * 4);
  for (int i = 0; i < 256; ++i) {
    ramp[i * 4] = ramp[i * 4 + 1] = ramp[i * 4 + 2] = i;
    ramp[i * 4 + 3] = 255;
  }
  for (int control = 1; control <= 6; ++control)
    for (float amount : {-.9f, .9f}) {
      auto p = Neutral();
      p[control] = amount;
      auto out = Render(ramp, p, 256, 1, 256, 1);
      for (size_t i = 4; i < out.size(); i += 4)
        EXPECT_TRUE(out[i] >= out[i - 4]);
    }
}
TEST(PhotoEditsEffectsAndTheirShapeParametersAffectPixels) {
  const auto src = Fixture();
  for (int strength : {11, 14, 17, 20, 23, 27, 28}) {
    auto p = Neutral();
    p[strength] = .8;
    const auto first = Render(src, p);
    EXPECT_TRUE(Diff(first, src) > .15);
    std::vector<int> shapes;
    if (strength == 11)
      shapes = {12, 13};
    if (strength == 14)
      shapes = {15, 16, 29};
    if (strength == 17)
      shapes = {18, 19};
    if (strength == 20)
      shapes = {21, 22};
    if (strength == 23)
      shapes = {24, 25, 26, 29};
    for (int shape : shapes) {
      auto q = p;
      q[shape] = shape == 29 ? 9521 : .9f;
      EXPECT_TRUE(Diff(first, Render(src, q)) > .05);
    }
  }
}
TEST(PhotoEditsNoiseSeedStableAndSpatialEffectsScale) {
  auto p = Neutral();
  p[14] = .8;
  p[23] = .6;
  const auto src = Fixture();
  EXPECT_TRUE(Render(src, p) == Render(src, p));
  // A uniform image excludes source resampling differences. Coordinates are
  // normalized.
  std::vector<uint8_t> small(64 * 32 * 4, 160), large(128 * 64 * 4, 160);
  p = Neutral();
  p[11] = .8;
  p[23] = .6;
  const auto a = Render(small, p, 64, 32, 64, 32),
             b = Render(large, p, 128, 64, 128, 64);
  if (a.empty() || b.empty())
    return;
  double delta = 0;
  for (int y = 1; y < 31; ++y)
    for (int x = 1; x < 63; ++x)
      for (int c = 0; c < 3; ++c)
        delta += std::abs(int(a[(y * 64 + x) * 4 + c]) -
                          int(b[((y * 2) * 128 + x * 2) * 4 + c]));
  EXPECT_TRUE(delta / (30 * 62 * 3) < 4);
}
TEST(PhotoEditsQuarterTurnsFlipsAndCropHaveHandCheckedCoordinates) {
  std::vector<uint8_t> src;
  for (int i = 1; i <= 6; ++i) {
    src.insert(src.end(), {uint8_t(i * 20), 0, 0, 255});
  }
  auto p = Neutral();
  p[34] = 1;
  p[30] = .5;
  p[32] = .5;
  auto out = Render(src, p, 3, 2, 1, 3);
  if (out.size() == 12) {
    EXPECT_EQ(out[0], 20);
    EXPECT_EQ(out[4], 40);
    EXPECT_EQ(out[8], 60);
  }
  p = Neutral();
  p[35] = 1;
  p[36] = 1;
  out = Render(src, p, 3, 2, 3, 2);
  if (out.size() == 24)
    for (int i = 0; i < 6; ++i)
      EXPECT_EQ(out[i * 4], (6 - i) * 20);
  p = Neutral();
  p[37] = 45;
  std::vector<uint8_t> solid(20 * 10 * 4, 180);
  out = Render(solid, p, 20, 10, 20, 10);
  EXPECT_TRUE(out == solid); // Scale to fill cannot introduce black corners.
}
TEST(PhotoEditsRejectInvalidInputWithoutAllocating) {
  auto src = Fixture();
  auto p = Neutral();
  uint8_t *out = reinterpret_cast<uint8_t *>(1);
  auto check = [&](const float *edits, int count, int w, int h, int tw,
                   int th) {
    out = reinterpret_cast<uint8_t *>(1);
    EXPECT_EQ(gremote_render_edit_rgba(src.data(), w, h, edits, count, nullptr,
                                       0, 1, tw, th, &out),
              GREMOTE_INVALID_ARGUMENT);
    EXPECT_TRUE(out == nullptr);
  };
  check(p.data(), 1061, 48, 32, 48, 32);
  check(nullptr, 1062, 48, 32, 48, 32);
  check(p.data(), 1062, 0, 32, 48, 32);
  check(p.data(), 1062, 48, 32, 49, 32);
  for (int index : {0, 1, 12, 29, 32, 34, 35, 37, 38}) {
    auto q = p;
    q[index] = std::numeric_limits<float>::quiet_NaN();
    check(q.data(), 1062, 48, 32, 48, 32);
  }
  p[30] = .8;
  p[32] = .5;
  check(p.data(), 1062, 48, 32, 10, 10);
  p = Neutral();
  p[34] = .5;
  check(p.data(), 1062, 48, 32, 48, 32);
  p = Neutral();
  p[39] = 1.1;
  check(p.data(), 1062, 48, 32, 48, 32);
}

#include "image.h"
#include "jpeg_io.h"
#include "test_util.h"
#include <chrono>
#include <fcntl.h>
#include <thread>
#include <unistd.h>

namespace {
std::vector<uint8_t> ToRgba(const gremote::Image &image) {
  std::vector<uint8_t> rgba(size_t(image.width) * image.height * 4);
  for (size_t i = 0; i < rgba.size() / 4; ++i) {
    std::memcpy(&rgba[i * 4], &image.pixels[i * 3], 3);
    rgba[i * 4 + 3] = 255;
  }
  return rgba;
}
gremote_export_request PhotoRequest(int fd, const std::string &path,
                                    const Edits &edits, int w, int h) {
  gremote_export_request r{};
  r.fd = fd;
  r.orientation = 1;
  r.lut_strength = 1;
  r.photo_width = r.canvas_width = w;
  r.photo_height = r.canvas_height = h;
  r.quality = 100;
  r.output_path = path.c_str();
  r.edits = edits.data();
  r.edit_count = edits.size();
  return r;
}
} // namespace
TEST(PhotoEditsPreviewMatchesDecodedJpegWithExifCropAndAllStages) {
  const auto source = gremote_test::TempPath("edits-source.jpg"),
             dest = gremote_test::TempPath("edits-export.jpg");
  EXPECT_EQ(
      gremote::EncodeJpegFile(gremote_test::Gradient(160, 120), source, 100),
      GREMOTE_OK);
  uint8_t *decoded = nullptr;
  int32_t w = 0, h = 0;
  EXPECT_EQ(gremote_decode_preview(open(source.c_str(), O_RDONLY), 6, 1000,
                                   &decoded, &w, &h),
            GREMOTE_OK);
  if (!decoded)
    return;
  const std::vector<uint8_t> pixels(decoded, decoded + size_t(w) * h * 4);
  gremote_free(decoded);
  auto p = Neutral();
  p[1] = .3;
  p[2] = .15;
  p[3] = -.2;
  p[4] = .2;
  p[5] = .1;
  p[6] = .1;
  p[7] = .1;
  p[8] = .2;
  p[9] = .2;
  p[10] = .2;
  p[11] = .2;
  p[14] = .15;
  p[17] = .4;
  p[20] = .4;
  p[23] = .2;
  p[27] = .1;
  p[28] = .1;
  p[30] = .125;
  p[31] = .1;
  p[32] = .75;
  p[33] = .8;
  p[34] = 1;
  p[35] = 1;
  p[37] = 8;
  for (int i = 0; i < 256; ++i)
    p[38 + i] = std::pow(i / 255.f, .9f);
  const auto preview = Render(pixels, p, w, h, 100, 70);
  auto request = PhotoRequest(open(source.c_str(), O_RDONLY), dest, p, 100, 70);
  request.orientation = 6;
  EXPECT_EQ(gremote_export_jpeg(&request, nullptr), GREMOTE_OK);
  EXPECT_TRUE(gremote_test::FdIsClosed(request.fd));
  EXPECT_TRUE(!gremote_test::FileExists(dest + ".part"));
  const auto bytes = gremote_test::ReadFile(dest);
  gremote::Image result;
  EXPECT_EQ(gremote::DecodeJpeg(bytes.data(), bytes.size(), 1, &result),
            GREMOTE_OK);
  EXPECT_EQ(result.width, 100);
  EXPECT_EQ(result.height, 70);
  double error = 0;
  int peak = 0;
  if (result.width == 100 && result.height == 70 &&
      preview.size() == 100 * 70 * 4) {
    for (size_t i = 0; i < 7000; ++i)
      for (int c = 0; c < 3; ++c) {
        int d = std::abs(int(preview[i * 4 + c]) - result.pixels[i * 3 + c]);
        error += d;
        peak = std::max(peak, d);
      }
    error /= 21000;
    EXPECT_TRUE(error < 5);
    std::printf("  Native same-size preview/JPEG mean RGB error %.4f, max %d "
                "(quality100, EXIF6+CW+flip+straighten+crop)\n",
                error, peak);
  }
  unlink(source.c_str());
  unlink(dest.c_str());
}
TEST(PhotoEditsLutRunsBetweenBasicAndCurvesWithoutChangingAlpha) {
  std::string cube = "LUT_3D_SIZE 17\n";
  for (int i = 0; i < 17 * 17 * 17; ++i)
    cube += "0.25 0.5 0.75\n";
  auto p = Neutral();
  p[1] = 2;
  for (int i = 0; i < 256; ++i)
    p[38 + i] = std::sqrt(i / 255.f);
  std::vector<uint8_t> src = {1, 2, 3, 77};
  uint8_t *out = nullptr;
  EXPECT_EQ(
      gremote_render_edit_rgba(src.data(), 1, 1, p.data(), 1062,
                               reinterpret_cast<const uint8_t *>(cube.data()),
                               cube.size(), 1, 1, 1, &out),
      GREMOTE_OK);
  if (out) {
    EXPECT_NEAR(out[0], 128, 1);
    EXPECT_NEAR(out[1], 180, 1);
    EXPECT_NEAR(out[2], 221, 1);
    EXPECT_EQ(out[3], 77);
    gremote_free(out);
  }
}
TEST(PhotoEditsGrainHasMatchingNormalizedCoordinatesAcrossResolutions) {
  const std::vector<uint8_t> small(32 * 16 * 4, 128), large(96 * 48 * 4, 128);
  auto p = Neutral();
  p[14] = .8;
  p[15] = .9;
  p[16] = .6;
  p[23] = .5;
  const auto a = Render(small, p, 32, 16, 32, 16),
             b = Render(large, p, 96, 48, 96, 48);
  if (a.empty() || b.empty())
    return;
  for (int y = 0; y < 16; ++y)
    for (int x = 0; x < 32; ++x)
      for (int c = 0; c < 4; ++c)
        EXPECT_NEAR(a[(y * 32 + x) * 4 + c],
                    b[((y * 3 + 1) * 96 + x * 3 + 1) * 4 + c], 1);
}
TEST(
    PhotoEditsExportRejectsMalformedParametersClosesFdAndPreservesExistingOutput) {
  const auto source = gremote_test::TempPath("invalid-edits-source.jpg"),
             dest = gremote_test::TempPath("invalid-edits.jpg");
  EXPECT_EQ(gremote::EncodeJpegFile(gremote_test::Gradient(40, 30), source, 90),
            GREMOTE_OK);
  EXPECT_EQ(gremote::EncodeJpegFile(gremote_test::Gradient(4, 3), dest, 90),
            GREMOTE_OK);
  const auto original = gremote_test::ReadFile(dest);
  auto p = Neutral();
  p[3] = 2;
  auto request = PhotoRequest(open(source.c_str(), O_RDONLY), dest, p, 40, 30);
  EXPECT_EQ(gremote_export_jpeg(&request, nullptr), GREMOTE_INVALID_ARGUMENT);
  EXPECT_TRUE(gremote_test::FdIsClosed(request.fd));
  EXPECT_TRUE(gremote_test::ReadFile(dest) == original);
  EXPECT_TRUE(!gremote_test::FileExists(dest + ".part"));
  request.fd = open(source.c_str(), O_RDONLY);
  request.edits = nullptr;
  request.edit_count = 1062;
  EXPECT_EQ(gremote_export_jpeg(&request, nullptr), GREMOTE_INVALID_ARGUMENT);
  EXPECT_TRUE(gremote_test::FdIsClosed(request.fd));
  unlink(source.c_str());
  unlink(dest.c_str());
}
TEST(PhotoEditsExportCancelsDuringProcessingAndPreservesAtomicDestination) {
  const auto source = gremote_test::TempPath("cancel-edits-source.jpg"),
             dest = gremote_test::TempPath("cancel-edits.jpg");
  EXPECT_EQ(
      gremote::EncodeJpegFile(gremote_test::Gradient(1024, 768), source, 90),
      GREMOTE_OK);
  EXPECT_EQ(gremote::EncodeJpegFile(gremote_test::Gradient(4, 3), dest, 90),
            GREMOTE_OK);
  const auto original = gremote_test::ReadFile(dest);
  auto p = Neutral();
  p[17] = p[20] = p[14] = .8;
  auto request =
      PhotoRequest(open(source.c_str(), O_RDONLY), dest, p, 1024, 768);
  volatile int32_t cancel = 0;
  std::thread stop([&]() {
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
    cancel = 1;
  });
  const int status = gremote_export_jpeg(&request, &cancel);
  stop.join();
  EXPECT_EQ(status, GREMOTE_CANCELLED);
  EXPECT_TRUE(gremote_test::FdIsClosed(request.fd));
  EXPECT_TRUE(gremote_test::ReadFile(dest) == original);
  EXPECT_TRUE(!gremote_test::FileExists(dest + ".part"));
  unlink(source.c_str());
  unlink(dest.c_str());
}
TEST(PhotoEditsRejectsAllMalformedRangesAndBufferDimensions) {
  const auto src = Fixture();
  const auto neutral = Neutral();
  auto check = [&](const Edits &p) {
    uint8_t *out = nullptr;
    EXPECT_EQ(gremote_render_edit_rgba(src.data(), 48, 32, p.data(), 1062,
                                       nullptr, 0, 1, 48, 32, &out),
              GREMOTE_INVALID_ARGUMENT);
    EXPECT_TRUE(out == nullptr);
  };
  for (int index = 0; index < 1062; ++index) {
    auto p = neutral;
    p[index] = std::numeric_limits<float>::infinity();
    check(p);
  }
  for (auto entry : std::vector<std::pair<int, float>>{{0, 3},
                                                       {1, -3.1f},
                                                       {1, 3.1f},
                                                       {2, 1.1f},
                                                       {10, -1.1f},
                                                       {11, -1.01f},
                                                       {28, 1.1f},
                                                       {29, 0},
                                                       {29, 1.5f},
                                                       {29, 16777216},
                                                       {30, -.1f},
                                                       {32, 0},
                                                       {33, 0},
                                                       {34, 4},
                                                       {35, .5f},
                                                       {36, -1},
                                                       {37, -46},
                                                       {38, -.1f},
                                                       {1061, 1.1f}}) {
    auto p = neutral;
    p[entry.first] = entry.second;
    check(p);
  }
  uint8_t *out = nullptr;
  EXPECT_EQ(gremote_render_edit_rgba(src.data(), 100000, 100000, neutral.data(),
                                     1062, nullptr, 0, 1, 1, 1, &out),
            GREMOTE_TOO_LARGE);
  EXPECT_EQ(gremote_render_edit_rgba(src.data(), 48, 32, neutral.data(), 1062,
                                     nullptr, -1, 1, 48, 32, &out),
            GREMOTE_INVALID_ARGUMENT);
  EXPECT_EQ(gremote_render_edit_rgba(src.data(), 48, 32, neutral.data(), 1062,
                                     nullptr, 20, 1, 48, 32, &out),
            GREMOTE_INVALID_ARGUMENT);
  EXPECT_EQ(gremote_render_edit_rgba(
                src.data(), 48, 32, neutral.data(), 1062, nullptr, 0,
                std::numeric_limits<float>::quiet_NaN(), 48, 32, &out),
            GREMOTE_INVALID_ARGUMENT);
}

TEST(PhotoEditsEveryQuarterTurnAndTinyEdgeCropPreserveCoordinates) {
  std::vector<uint8_t> src;
  for (int i = 1; i <= 6; ++i)
    src.insert(src.end(), {uint8_t(i * 20), 0, 0, 255});
  const int expected[4][6] = {{20, 40, 60, 80, 100, 120},
                              {80, 20, 100, 40, 120, 60},
                              {120, 100, 80, 60, 40, 20},
                              {60, 120, 40, 100, 20, 80}};
  for (int turn = 0; turn < 4; ++turn) {
    auto p = Neutral();
    p[34] = turn;
    const auto out = Render(src, p, 3, 2, turn % 2 ? 2 : 3, turn % 2 ? 3 : 2);
    if (out.size() == 24)
      for (int i = 0; i < 6; ++i)
        EXPECT_EQ(out[i * 4], expected[turn][i]);
  }
  auto p = Neutral();
  p[30] = .999f;
  p[31] = .999f;
  p[32] = .0001f;
  p[33] = .0001f;
  const auto out = Render(src, p, 3, 2, 1, 1);
  if (out.size() == 4) {
    EXPECT_EQ(out[0], 120);
    EXPECT_EQ(out[3], 255);
  }
}
TEST(PhotoEditsBlurRadiusFollowsNormalizedImageScale) {
  auto source = [](int size) {
    std::vector<uint8_t> pixels(size * size * 4, 80);
    for (int y = 0; y < size; ++y)
      for (int x = 0; x < size; ++x) {
        auto *p = &pixels[(y * size + x) * 4];
        p[3] = 255;
        if (x >= size / 4 && x < size * 3 / 4 && y >= size / 4 &&
            y < size * 3 / 4)
          p[0] = p[1] = p[2] = 255;
      }
    return pixels;
  };
  auto p = Neutral();
  p[17] = p[20] = .8;
  p[18] = p[21] = .9;
  const auto a = Render(source(64), p, 64, 64, 64, 64),
             b = Render(source(192), p, 192, 192, 192, 192);
  if (a.empty() || b.empty())
    return;
  double delta = 0;
  for (int y = 0; y < 64; ++y)
    for (int x = 0; x < 64; ++x)
      for (int c = 0; c < 3; ++c)
        delta += std::abs(int(a[(y * 64 + x) * 4 + c]) -
                          int(b[((y * 3 + 1) * 192 + x * 3 + 1) * 4 + c]));
  delta /= 64 * 64 * 3;
  EXPECT_TRUE(delta < 3);
  std::printf(
      "  Native normalized glow radius scale64/192 mean RGB deviation %.4f\n",
      delta);
}
TEST(PhotoEditsGlowHandlesSingleRowPanoramasAndOnePixelImages) {
  auto p = Neutral();
  p[17] = p[20] = .8;
  p[18] = p[21] = 1;
  std::vector<uint8_t> panorama(4096 * 4, 250);
  const auto out = Render(panorama, p, 4096, 1, 4096, 1);
  EXPECT_EQ(out.size(), panorama.size());
  if (!out.empty())
    for (size_t i = 3; i < out.size(); i += 4)
      EXPECT_EQ(out[i], 250);
  const std::vector<uint8_t> pixel = {250, 250, 250, 123};
  const auto one = Render(pixel, p, 1, 1, 1, 1);
  if (!one.empty()) {
    EXPECT_TRUE(one[0] >= 250);
    EXPECT_EQ(one[3], 123);
  }
}

TEST(PhotoEditsSignedVignetteBrightensAndDarkensCorners) {
  std::vector<uint8_t> src(48 * 32 * 4, 96);
  for (size_t i = 3; i < src.size(); i += 4)
    src[i] = 123;
  auto dark = Neutral();
  dark[11] = .8;
  auto bright = dark;
  bright[11] = -.8;
  const auto darker = Render(src, dark), brighter = Render(src, bright);
  EXPECT_EQ(brighter.size(), src.size());
  if (darker.size() != src.size() || brighter.size() != src.size())
    return;
  EXPECT_TRUE(darker[0] < 96);
  EXPECT_TRUE(brighter[0] > 96);
  const size_t center = (16 * 48 + 24) * 4;
  EXPECT_EQ(darker[center], 96);
  EXPECT_EQ(brighter[center], 96);
  for (size_t i = 3; i < src.size(); i += 4)
    EXPECT_EQ(brighter[i], 123);
}
TEST(PhotoEditsDescendingAndReversingCurvesRenderUserDefinedTones) {
  const std::vector<uint8_t> source = {32, 96, 160, 177};
  auto inverted = Neutral();
  for (int i = 0; i < 256; ++i)
    inverted[38 + i] = 1 - i / 255.f;
  const auto out = Render(source, inverted, 1, 1, 1, 1);
  EXPECT_EQ(out.size(), source.size());
  if (out.size() != source.size())
    return;
  EXPECT_NEAR(out[0], 223, 1);
  EXPECT_NEAR(out[1], 159, 1);
  EXPECT_NEAR(out[2], 95, 1);
  EXPECT_EQ(out[3], 177);
  auto reversing = Neutral();
  for (int i = 0; i < 256; ++i)
    reversing[38 + i] = i <= 128 ? i / 128.f : (255 - i) / 127.f;
  const auto shaped = Render(source, reversing, 1, 1, 1, 1);
  EXPECT_EQ(shaped.size(), source.size());
  if (shaped.size() != source.size())
    return;
  EXPECT_NEAR(shaped[0], 64, 1);
  EXPECT_NEAR(shaped[1], 191, 1);
  EXPECT_NEAR(shaped[2], 191, 1);
  EXPECT_EQ(shaped[3], 177);
}
