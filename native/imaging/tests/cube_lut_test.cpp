#include <cstdint>
#include <random>
#include <string>
#include <vector>

#include "cube_lut.h"
#include "gremote_imaging.h"
#include "test_main.h"

namespace {

template <typename F>
std::string MakeCube(int size, F transform, const std::string& header = "") {
  std::string text = "# generated\nTITLE \"test\"\n" + header;
  text += "LUT_3D_SIZE " + std::to_string(size) + "\n";
  char line[96];
  for (int b = 0; b < size; ++b) {
    for (int g = 0; g < size; ++g) {
      for (int r = 0; r < size; ++r) {
        float rgb[3] = {r / float(size - 1), g / float(size - 1),
                        b / float(size - 1)};
        transform(rgb);
        std::snprintf(line, sizeof(line), "%.6f %.6f %.6f\n", rgb[0], rgb[1],
                      rgb[2]);
        text += line;
      }
    }
  }
  return text;
}

void Identity(float*) {}
void SwapRedBlue(float* rgb) { std::swap(rgb[0], rgb[2]); }

int Parse(const std::string& text, gremote::CubeLut* lut) {
  return gremote::ParseCube(reinterpret_cast<const uint8_t*>(text.data()),
                         text.size(), lut);
}

std::vector<uint8_t> GrayRamp() {
  std::vector<uint8_t> pixels;
  for (int v = 0; v < 256; ++v) {
    pixels.insert(pixels.end(), {uint8_t(v), uint8_t(v), uint8_t(v)});
  }
  return pixels;
}

}  // namespace

TEST(ParsesIdentityCubesOfSupportedSizes) {
  for (int size : {2, 16, 17, 25, 32, 33, 64, 65}) {
    gremote::CubeLut lut;
    EXPECT_EQ(Parse(MakeCube(size, Identity), &lut), GREMOTE_OK);
    EXPECT_EQ(lut.size, size);
    EXPECT_EQ(lut.table.size(), size_t(size) * size * size * 3);
  }
}

TEST(ParsesDomainAndSkipsComments) {
  gremote::CubeLut lut;
  const auto text = MakeCube(17, Identity,
                             "DOMAIN_MIN 0 0 0\nDOMAIN_MAX 1 1 1\n# note\n\n");
  EXPECT_EQ(Parse(text, &lut), GREMOTE_OK);
  EXPECT_NEAR(lut.domain_max[1], 1.0, 1e-6);
}

TEST(RejectsUnsupportedSize) {
  gremote::CubeLut lut;
  EXPECT_EQ(Parse("LUT_3D_SIZE 1\n", &lut), GREMOTE_LUT_PARSE);
  EXPECT_EQ(Parse("LUT_3D_SIZE 129\n", &lut), GREMOTE_LUT_PARSE);
  EXPECT_EQ(Parse("LUT_3D_SIZE 100000000000000000000\n", &lut), GREMOTE_LUT_PARSE);
}

TEST(RejectsWrongRowCount) {
  gremote::CubeLut lut;
  auto text = MakeCube(17, Identity);
  text += "0.5 0.5 0.5\n";
  EXPECT_EQ(Parse(text, &lut), GREMOTE_LUT_PARSE);
  auto truncated = MakeCube(17, Identity);
  truncated.resize(truncated.size() - 30);
  EXPECT_EQ(Parse(truncated, &lut), GREMOTE_LUT_PARSE);
}

TEST(RejectsNonNumericAndNaN) {
  gremote::CubeLut lut;
  auto text = MakeCube(17, Identity);
  const auto at = text.find("0.000000 0.000000 0.000000");
  auto bad = text;
  bad.replace(at, 8, "abcdefgh");
  EXPECT_EQ(Parse(bad, &lut), GREMOTE_LUT_PARSE);
  auto nan = text;
  nan.replace(at, 8, "nan     ");
  EXPECT_EQ(Parse(nan, &lut), GREMOTE_LUT_PARSE);
}

TEST(RejectsOutOfRangeValues) {
  gremote::CubeLut lut;
  auto text = MakeCube(17, Identity);
  text.replace(text.find("0.000000 0.000000 0.000000"), 8, "1.500000");
  EXPECT_EQ(Parse(text, &lut), GREMOTE_LUT_RANGE);
}

TEST(RejectsMissingSizeAndInvertedDomain) {
  gremote::CubeLut lut;
  EXPECT_EQ(Parse("0 0 0\n", &lut), GREMOTE_LUT_PARSE);
  EXPECT_EQ(Parse(MakeCube(17, Identity, "DOMAIN_MIN 1 1 1\nDOMAIN_MAX 0 0 0\n"),
                  &lut),
            GREMOTE_LUT_PARSE);
}

TEST(IdentityLutLeavesPixelsUnchanged) {
  gremote::CubeLut lut;
  Parse(MakeCube(33, Identity), &lut);
  auto pixels = GrayRamp();
  std::mt19937 random(7);
  for (int i = 0; i < 3000; ++i) pixels.push_back(uint8_t(random() & 0xff));
  const auto original = pixels;
  const int width = int(pixels.size() / 3);
  gremote::ApplyLut(pixels.data(), width, 1, width * 3, 3, lut, 1.0f);
  EXPECT_TRUE(pixels == original);
}

TEST(SwapLutIsExactOnGridPoints) {
  gremote::CubeLut lut;
  Parse(MakeCube(17, SwapRedBlue), &lut);
  // 255 maps to the last grid point and 0 to the first.
  std::vector<uint8_t> rgba = {255, 0, 0, 77, 0, 255, 255, 9};
  gremote::ApplyLut(rgba.data(), 2, 1, 8, 4, lut, 1.0f);
  EXPECT_EQ(int(rgba[0]), 0);
  EXPECT_EQ(int(rgba[2]), 255);
  EXPECT_EQ(int(rgba[3]), 77);
  EXPECT_EQ(int(rgba[4]), 255);
  EXPECT_EQ(int(rgba[6]), 0);
  EXPECT_EQ(int(rgba[7]), 9);
}

TEST(StrengthBlendsWithOriginal) {
  gremote::CubeLut lut;
  Parse(MakeCube(17, SwapRedBlue), &lut);
  std::vector<uint8_t> none = {255, 0, 0};
  gremote::ApplyLut(none.data(), 1, 1, 3, 3, lut, 0.0f);
  EXPECT_EQ(int(none[0]), 255);
  EXPECT_EQ(int(none[2]), 0);
  std::vector<uint8_t> half = {255, 0, 0};
  gremote::ApplyLut(half.data(), 1, 1, 3, 3, lut, 0.5f);
  EXPECT_NEAR(half[0], 128, 1);
  EXPECT_NEAR(half[2], 128, 1);
}

TEST(AppliesAcrossManyRowsWithStride) {
  gremote::CubeLut lut;
  Parse(MakeCube(17, SwapRedBlue), &lut);
  const int width = 3, height = 101, stride = width * 3 + 5;
  std::vector<uint8_t> pixels(size_t(stride) * height, 42);
  for (int y = 0; y < height; ++y) {
    for (int x = 0; x < width; ++x) {
      uint8_t* p = &pixels[size_t(y) * stride + x * 3];
      p[0] = 255;
      p[1] = 0;
      p[2] = 0;
    }
  }
  gremote::ApplyLut(pixels.data(), width, height, stride, 3, lut, 1.0f);
  for (int y = 0; y < height; ++y) {
    const uint8_t* row = &pixels[size_t(y) * stride];
    EXPECT_EQ(int(row[0]), 0);
    EXPECT_EQ(int(row[2]), 255);
    EXPECT_EQ(int(row[width * 3]), 42);
  }
}
