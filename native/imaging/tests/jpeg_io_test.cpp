#include <sys/stat.h>

#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

#include "image.h"
#include "jpeg_io.h"
#include "gremote_imaging.h"
#include "test_main.h"
#include "test_util.h"

TEST(JpegRoundTripKeepsSizeAndColor) {
  const auto source = gremote_test::Gradient(64, 48);
  const auto path = gremote_test::TempPath("roundtrip.jpg");
  EXPECT_EQ(gremote::EncodeJpegFile(source, path, 95), GREMOTE_OK);
  const auto bytes = gremote_test::ReadFile(path);
  gremote::Image decoded;
  EXPECT_EQ(gremote::DecodeJpeg(bytes.data(), bytes.size(), 1, &decoded), GREMOTE_OK);
  EXPECT_EQ(decoded.width, 64);
  EXPECT_EQ(decoded.height, 48);
  EXPECT_EQ(decoded.channels, 3);
  EXPECT_NEAR(gremote_test::MeanAbsDiff(source, decoded), 0, 3);
}

TEST(ScaledDecodeShrinksByDenominator) {
  const auto path = gremote_test::TempPath("scaled.jpg");
  gremote::EncodeJpegFile(gremote_test::Gradient(64, 48), path, 90);
  const auto bytes = gremote_test::ReadFile(path);
  gremote::Image decoded;
  EXPECT_EQ(gremote::DecodeJpeg(bytes.data(), bytes.size(), 4, &decoded), GREMOTE_OK);
  EXPECT_EQ(decoded.width, 16);
  EXPECT_EQ(decoded.height, 12);
}

TEST(ChoosesLargestScaleThatStillCoversTarget) {
  EXPECT_EQ(gremote::ChooseScaleDenom(6000, 4000, 2048), 2);
  EXPECT_EQ(gremote::ChooseScaleDenom(6000, 4000, 700), 8);
  EXPECT_EQ(gremote::ChooseScaleDenom(4000, 6000, 1400), 4);
  EXPECT_EQ(gremote::ChooseScaleDenom(1000, 800, 2048), 1);
}

TEST(ReadsHeaderSize) {
  const auto path = gremote_test::TempPath("header.jpg");
  gremote::EncodeJpegFile(gremote_test::Gradient(30, 20), path, 90);
  const auto bytes = gremote_test::ReadFile(path);
  int width = 0, height = 0;
  EXPECT_EQ(gremote::ReadJpegSize(bytes.data(), bytes.size(), &width, &height),
            GREMOTE_OK);
  EXPECT_EQ(width, 30);
  EXPECT_EQ(height, 20);
}

TEST(RejectsCorruptData) {
  std::vector<uint8_t> junk = {0xFF, 0xD8, 0x00, 0x11, 0x22};
  gremote::Image decoded;
  EXPECT_EQ(gremote::DecodeJpeg(junk.data(), junk.size(), 1, &decoded),
            GREMOTE_DECODE);
  EXPECT_EQ(gremote::DecodeJpeg(nullptr, 0, 1, &decoded), GREMOTE_DECODE);
}

TEST(RejectsImagesOverPixelBudget) {
  const auto path = gremote_test::TempPath("huge.jpg");
  gremote::EncodeJpegFile(gremote_test::Gradient(16, 16), path, 90);
  auto bytes = gremote_test::ReadFile(path);
  EXPECT_TRUE(gremote_test::PatchSofSize(&bytes, 12000, 9000));
  gremote::Image decoded;
  EXPECT_EQ(gremote::DecodeJpeg(bytes.data(), bytes.size(), 1, &decoded),
            GREMOTE_TOO_LARGE);
}

TEST(RowWriterFailsWhenRowsAreMissing) {
  const auto path = gremote_test::TempPath("short.jpg");
  gremote::JpegRowWriter writer;
  EXPECT_EQ(writer.Open(path, 4, 4, 90), GREMOTE_OK);
  std::vector<uint8_t> row(12, 128);
  EXPECT_EQ(writer.WriteRow(row.data()), GREMOTE_OK);
  EXPECT_EQ(writer.WriteRow(row.data()), GREMOTE_OK);
  EXPECT_EQ(writer.Finish(), GREMOTE_ENCODE);
  EXPECT_TRUE(!gremote_test::FileExists(path));
  EXPECT_TRUE(!gremote_test::FileExists(path + ".part"));
}

TEST(RowWriterRejectsBadArguments) {
  gremote::JpegRowWriter writer;
  EXPECT_EQ(writer.Open(gremote_test::TempPath("bad.jpg"), 0, 4, 90),
            GREMOTE_INVALID_ARGUMENT);
  gremote::JpegRowWriter quality;
  EXPECT_EQ(quality.Open(gremote_test::TempPath("bad.jpg"), 4, 4, 101),
            GREMOTE_INVALID_ARGUMENT);
  gremote::JpegRowWriter io;
  EXPECT_EQ(io.Open("/nonexistent-dir/x.jpg", 4, 4, 90), GREMOTE_IO);
}
