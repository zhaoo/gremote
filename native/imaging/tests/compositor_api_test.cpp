#include <fcntl.h>
#include <unistd.h>

#include <cstdlib>
#include <string>
#include <vector>

#include "frame_compositor.h"
#include "image.h"
#include "jpeg_io.h"
#include "gremote_imaging.h"
#include "test_main.h"
#include "test_util.h"

namespace {

gremote::Image Solid(int width, int height, uint8_t r, uint8_t g, uint8_t b) {
  gremote::Image image(width, height, 3);
  for (size_t i = 0; i < image.pixels.size(); i += 3) {
    image.pixels[i] = r;
    image.pixels[i + 1] = g;
    image.pixels[i + 2] = b;
  }
  return image;
}

std::vector<uint8_t> ComposeAll(const gremote::FrameSpec& spec) {
  std::vector<uint8_t> out(size_t(spec.canvas_width) * spec.canvas_height * 3);
  for (int y = 0; y < spec.canvas_height; ++y) {
    gremote::ComposeRow(spec, y, &out[size_t(y) * spec.canvas_width * 3]);
  }
  return out;
}

const uint8_t* At(const std::vector<uint8_t>& out, int width, int x, int y) {
  return &out[(size_t(y) * width + x) * 3];
}

std::string WriteSourceJpeg(const std::string& name, int width, int height) {
  const auto path = gremote_test::TempPath(name);
  gremote::EncodeJpegFile(gremote_test::Gradient(width, height), path, 92);
  return path;
}

gremote_export_request BasicRequest(int fd, const std::string& output) {
  gremote_export_request request{};
  request.fd = fd;
  request.orientation = 1;
  request.lut_strength = 1.0f;
  request.photo_width = 40;
  request.photo_height = 30;
  request.photo_x = 5;
  request.photo_y = 5;
  request.canvas_width = 50;
  request.canvas_height = 50;
  request.background_r = 255;
  request.background_g = 255;
  request.background_b = 255;
  request.quality = 90;
  request.output_path = output.c_str();
  return request;
}

}  // namespace

TEST(ComposerFillsBackgroundAndPlacesPhoto) {
  const auto photo = Solid(4, 3, 10, 20, 30);
  gremote::FrameSpec spec;
  spec.canvas_width = 8;
  spec.canvas_height = 7;
  spec.background[0] = 250;
  spec.background[1] = 240;
  spec.background[2] = 230;
  spec.photo = &photo;
  spec.photo_x = 2;
  spec.photo_y = 1;
  EXPECT_EQ(gremote::ValidateFrame(spec), GREMOTE_OK);
  const auto out = ComposeAll(spec);
  EXPECT_EQ(int(At(out, 8, 0, 0)[0]), 250);
  EXPECT_EQ(int(At(out, 8, 7, 6)[2]), 230);
  EXPECT_EQ(int(At(out, 8, 2, 1)[0]), 10);
  EXPECT_EQ(int(At(out, 8, 5, 3)[2]), 30);
  EXPECT_EQ(int(At(out, 8, 6, 3)[0]), 250);
  EXPECT_EQ(int(At(out, 8, 2, 4)[0]), 250);
}

TEST(ComposerBlendsStraightAlphaOverlays) {
  const auto photo = Solid(2, 2, 0, 0, 0);
  std::vector<uint8_t> rgba = {255, 0, 0, 255, 255, 0, 0, 128,
                               0, 0, 255, 0, 0, 0, 255, 128};
  gremote::FrameSpec spec;
  spec.canvas_width = 4;
  spec.canvas_height = 2;
  spec.background[0] = spec.background[1] = spec.background[2] = 255;
  spec.photo = &photo;
  spec.photo_x = 2;
  spec.photo_y = 0;
  spec.overlays.push_back({1, 0, 2, 2, rgba.data()});
  EXPECT_EQ(gremote::ValidateFrame(spec), GREMOTE_OK);
  const auto out = ComposeAll(spec);
  // Opaque red over white background.
  EXPECT_EQ(int(At(out, 4, 1, 0)[0]), 255);
  EXPECT_EQ(int(At(out, 4, 1, 0)[1]), 0);
  // Half red over the black photo.
  EXPECT_NEAR(At(out, 4, 2, 0)[0], 128, 1);
  EXPECT_EQ(int(At(out, 4, 2, 0)[1]), 0);
  // Transparent pixel keeps background.
  EXPECT_EQ(int(At(out, 4, 1, 1)[1]), 255);
  // Half blue over black photo.
  EXPECT_NEAR(At(out, 4, 2, 1)[2], 128, 1);
}

TEST(ComposerRejectsOutOfBoundsGeometry) {
  const auto photo = Solid(4, 4, 0, 0, 0);
  gremote::FrameSpec spec;
  spec.canvas_width = 5;
  spec.canvas_height = 5;
  spec.photo = &photo;
  spec.photo_x = 2;
  EXPECT_EQ(gremote::ValidateFrame(spec), GREMOTE_INVALID_ARGUMENT);
  spec.photo_x = 0;
  std::vector<uint8_t> rgba(4 * 4 * 4, 255);
  spec.overlays.push_back({3, 3, 4, 4, rgba.data()});
  EXPECT_EQ(gremote::ValidateFrame(spec), GREMOTE_INVALID_ARGUMENT);
  spec.overlays[0] = {0, 0, 4, 4, nullptr};
  EXPECT_EQ(gremote::ValidateFrame(spec), GREMOTE_INVALID_ARGUMENT);
}

TEST(ExportWritesCanvasSizedJpegAndClosesFd) {
  const auto source = WriteSourceJpeg("export-src.jpg", 80, 60);
  const auto output = gremote_test::TempPath("export-out.jpg");
  const int fd = open(source.c_str(), O_RDONLY);
  std::vector<uint8_t> strip(50 * 4 * 4, 0);
  for (size_t i = 3; i < strip.size(); i += 4) strip[i] = 255;
  gremote_overlay overlay{0, 42, 50, 4, strip.data()};
  auto request = BasicRequest(fd, output);
  request.overlays = &overlay;
  request.overlay_count = 1;
  EXPECT_EQ(gremote_export_jpeg(&request, nullptr), GREMOTE_OK);
  EXPECT_TRUE(gremote_test::FdIsClosed(fd));
  EXPECT_TRUE(!gremote_test::FileExists(output + ".part"));
  const auto bytes = gremote_test::ReadFile(output);
  gremote::Image decoded;
  EXPECT_EQ(gremote::DecodeJpeg(bytes.data(), bytes.size(), 1, &decoded), GREMOTE_OK);
  EXPECT_EQ(decoded.width, 50);
  EXPECT_EQ(decoded.height, 50);
  // Background corner stays white, overlay strip is black.
  EXPECT_TRUE(decoded.Row(0)[0] > 240);
  EXPECT_TRUE(decoded.Row(43)[3 * 25] < 20);
}

TEST(ExportAppliesLutAndOrientation) {
  const auto source = WriteSourceJpeg("export-rot.jpg", 60, 40);
  const auto output = gremote_test::TempPath("export-rot-out.jpg");
  const int fd = open(source.c_str(), O_RDONLY);
  auto request = BasicRequest(fd, output);
  request.orientation = 6;
  request.photo_width = 40;
  request.photo_height = 60;
  request.photo_x = 0;
  request.photo_y = 0;
  request.canvas_width = 40;
  request.canvas_height = 60;
  std::string cube = "LUT_3D_SIZE 1\n0 0 0\n";
  request.cube = reinterpret_cast<const uint8_t*>(cube.data());
  request.cube_length = int64_t(cube.size());
  // A 3D LUT needs at least two points per axis.
  EXPECT_EQ(gremote_export_jpeg(&request, nullptr), GREMOTE_LUT_PARSE);
  EXPECT_TRUE(gremote_test::FdIsClosed(fd));
  EXPECT_TRUE(!gremote_test::FileExists(output));

  std::string black = "LUT_3D_SIZE 17\n";
  for (int i = 0; i < 17 * 17 * 17; ++i) black += "0 0 0\n";
  const int fd2 = open(source.c_str(), O_RDONLY);
  request.fd = fd2;
  request.cube = reinterpret_cast<const uint8_t*>(black.data());
  request.cube_length = int64_t(black.size());
  EXPECT_EQ(gremote_export_jpeg(&request, nullptr), GREMOTE_OK);
  const auto bytes = gremote_test::ReadFile(output);
  gremote::Image decoded;
  gremote::DecodeJpeg(bytes.data(), bytes.size(), 1, &decoded);
  EXPECT_EQ(decoded.width, 40);
  EXPECT_EQ(decoded.height, 60);
  EXPECT_TRUE(decoded.Row(30)[60] < 8);
}

TEST(ExportRejectsUpscalingAndBadGeometry) {
  const auto source = WriteSourceJpeg("export-up.jpg", 20, 10);
  const auto output = gremote_test::TempPath("export-up-out.jpg");
  const int fd = open(source.c_str(), O_RDONLY);
  auto request = BasicRequest(fd, output);
  EXPECT_EQ(gremote_export_jpeg(&request, nullptr), GREMOTE_INVALID_ARGUMENT);
  EXPECT_TRUE(gremote_test::FdIsClosed(fd));
  EXPECT_EQ(gremote_export_jpeg(nullptr, nullptr), GREMOTE_INVALID_ARGUMENT);
}

TEST(ExportHonoursCancellation) {
  const auto source = WriteSourceJpeg("export-cancel.jpg", 80, 60);
  const auto output = gremote_test::TempPath("export-cancel-out.jpg");
  const int fd = open(source.c_str(), O_RDONLY);
  auto request = BasicRequest(fd, output);
  volatile int32_t cancel = 1;
  EXPECT_EQ(gremote_export_jpeg(&request, &cancel), GREMOTE_CANCELLED);
  EXPECT_TRUE(gremote_test::FdIsClosed(fd));
  EXPECT_TRUE(!gremote_test::FileExists(output));
  EXPECT_TRUE(!gremote_test::FileExists(output + ".part"));
}

TEST(PreviewIsOrientedAndBounded) {
  const auto source = WriteSourceJpeg("preview.jpg", 120, 80);
  const int fd = open(source.c_str(), O_RDONLY);
  uint8_t* rgba = nullptr;
  int32_t width = 0, height = 0;
  EXPECT_EQ(gremote_decode_preview(fd, 6, 50, &rgba, &width, &height), GREMOTE_OK);
  EXPECT_TRUE(gremote_test::FdIsClosed(fd));
  EXPECT_EQ(width, 33);
  EXPECT_EQ(height, 50);
  EXPECT_EQ(int(rgba[3]), 255);
  gremote_free(rgba);

  const int bad = open(source.c_str(), O_RDONLY);
  EXPECT_EQ(gremote_decode_preview(bad, 1, 0, &rgba, &width, &height),
            GREMOTE_INVALID_ARGUMENT);
  EXPECT_TRUE(gremote_test::FdIsClosed(bad));
}

TEST(ValidateAndApplyLutThroughCApi) {
  std::string cube = "LUT_3D_SIZE 17\n";
  for (int b = 0; b < 17; ++b)
    for (int g = 0; g < 17; ++g)
      for (int r = 0; r < 17; ++r)
        cube += std::to_string(b / 16.0) + " " + std::to_string(g / 16.0) +
                " " + std::to_string(r / 16.0) + "\n";
  const auto* bytes = reinterpret_cast<const uint8_t*>(cube.data());
  int32_t size = 0;
  EXPECT_EQ(gremote_lut_validate(bytes, int64_t(cube.size()), &size), GREMOTE_OK);
  EXPECT_EQ(size, 17);
  std::vector<uint8_t> rgba = {255, 0, 0, 200};
  EXPECT_EQ(gremote_apply_lut_rgba(rgba.data(), 1, 1, bytes, int64_t(cube.size()),
                                1.0f),
            GREMOTE_OK);
  EXPECT_EQ(int(rgba[0]), 0);
  EXPECT_EQ(int(rgba[2]), 255);
  EXPECT_EQ(int(rgba[3]), 200);
  const std::string junk = "hello";
  EXPECT_EQ(gremote_lut_validate(reinterpret_cast<const uint8_t*>(junk.data()),
                              int64_t(junk.size()), &size),
            GREMOTE_LUT_PARSE);
}
