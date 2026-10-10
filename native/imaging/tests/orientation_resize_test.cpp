#include <cstdint>
#include <vector>

#include "image.h"
#include "orientation.h"
#include "resize.h"
#include "test_main.h"

namespace {

// 2 wide, 3 tall, one channel; value = y * 2 + x.
gremote::Image Sample() {
  gremote::Image image(2, 3, 1);
  for (int i = 0; i < 6; ++i) image.pixels[i] = uint8_t(i);
  return image;
}

std::vector<int> Values(const gremote::Image& image) {
  return std::vector<int>(image.pixels.begin(), image.pixels.end());
}

}  // namespace

TEST(OrientationKeepsOrMirrorsLandscapeCases) {
  const auto source = Sample();
  // 0 1
  // 2 3
  // 4 5
  EXPECT_TRUE(Values(gremote::Orient(source, 1)) ==
              (std::vector<int>{0, 1, 2, 3, 4, 5}));
  EXPECT_TRUE(Values(gremote::Orient(source, 2)) ==
              (std::vector<int>{1, 0, 3, 2, 5, 4}));
  EXPECT_TRUE(Values(gremote::Orient(source, 3)) ==
              (std::vector<int>{5, 4, 3, 2, 1, 0}));
  EXPECT_TRUE(Values(gremote::Orient(source, 4)) ==
              (std::vector<int>{4, 5, 2, 3, 0, 1}));
  EXPECT_EQ(gremote::Orient(source, 3).width, 2);
}

TEST(OrientationSwapsDimensionsForRotations) {
  const auto source = Sample();
  const auto cw = gremote::Orient(source, 6);
  EXPECT_EQ(cw.width, 3);
  EXPECT_EQ(cw.height, 2);
  EXPECT_TRUE(Values(cw) == (std::vector<int>{4, 2, 0, 5, 3, 1}));
  EXPECT_TRUE(Values(gremote::Orient(source, 8)) ==
              (std::vector<int>{1, 3, 5, 0, 2, 4}));
  EXPECT_TRUE(Values(gremote::Orient(source, 5)) ==
              (std::vector<int>{0, 2, 4, 1, 3, 5}));
  EXPECT_TRUE(Values(gremote::Orient(source, 7)) ==
              (std::vector<int>{5, 3, 1, 4, 2, 0}));
}

TEST(OrientationTreatsUnknownValuesAsNormal) {
  EXPECT_TRUE(Values(gremote::Orient(Sample(), 0)) ==
              (std::vector<int>{0, 1, 2, 3, 4, 5}));
  EXPECT_TRUE(Values(gremote::Orient(Sample(), 9)) ==
              (std::vector<int>{0, 1, 2, 3, 4, 5}));
}

TEST(OrientationPreservesChannels) {
  gremote::Image rgb(2, 1, 3);
  rgb.pixels = {1, 2, 3, 4, 5, 6};
  const auto flipped = gremote::Orient(rgb, 2);
  EXPECT_TRUE(Values(flipped) == (std::vector<int>{4, 5, 6, 1, 2, 3}));
}

TEST(AreaResizeAveragesBlocks) {
  gremote::Image image(4, 4, 1);
  for (int y = 0; y < 4; ++y) {
    for (int x = 0; x < 4; ++x) image.pixels[y * 4 + x] = uint8_t((x / 2) * 100 + (y / 2) * 40 + (x % 2) * 2);
  }
  const auto half = gremote::ResizeArea(image, 2, 2);
  EXPECT_EQ(half.width, 2);
  EXPECT_EQ(half.height, 2);
  EXPECT_EQ(int(half.pixels[0]), 1);
  EXPECT_EQ(int(half.pixels[1]), 101);
  EXPECT_EQ(int(half.pixels[2]), 41);
  EXPECT_EQ(int(half.pixels[3]), 141);
}

TEST(AreaResizeNeverUpscales) {
  const auto source = Sample();
  const auto same = gremote::ResizeArea(source, 4, 6);
  EXPECT_EQ(same.width, 2);
  EXPECT_EQ(same.height, 3);
  EXPECT_TRUE(Values(same) == Values(source));
}

TEST(AreaResizeKeepsMeanForFractionalScale) {
  gremote::Image image(5, 5, 3);
  double sum = 0;
  for (size_t i = 0; i < image.pixels.size(); ++i) {
    image.pixels[i] = uint8_t((i * 37) % 251);
    sum += image.pixels[i];
  }
  const auto small = gremote::ResizeArea(image, 3, 3);
  double small_sum = 0;
  for (auto v : small.pixels) small_sum += v;
  EXPECT_NEAR(small_sum / small.pixels.size(), sum / image.pixels.size(), 1.0);
  gremote::Image flat(5, 5, 1);
  std::fill(flat.pixels.begin(), flat.pixels.end(), 200);
  for (auto v : gremote::ResizeArea(flat, 3, 2).pixels) EXPECT_EQ(int(v), 200);
}
