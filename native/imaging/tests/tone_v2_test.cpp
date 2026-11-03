#include "test_main.h"
#include "photo_edits.h"
#include "tone_v2.h"
#include "gremote_imaging.h"

namespace {
gremote::Image Ramp() {
  gremote::Image image(256, 1, 4);
  for (int x=0; x<256; ++x) {
    for (int c=0; c<3; ++c) image.pixels[x*4+c]=uint8_t(x);
    image.pixels[x*4+3]=uint8_t((x*17)%256);
  }
  return image;
}
gremote::Image Render(const gremote::PhotoEdits& edits) {
  gremote::Image out;
  EXPECT_EQ(gremote::RenderPhoto(Ramp(), edits, nullptr, 1, 256, 1, &out), GREMOTE_OK);
  return out;
}
}
TEST(ToneV2ParsesVersionAndRejectsFutureVersions) {
  gremote::PhotoEdits p, parsed;
  p.values[0]=2;
  EXPECT_EQ(gremote::ParsePhotoEdits(p.values.data(), p.values.size(), &parsed), GREMOTE_OK);
  EXPECT_EQ(parsed.values[0], 2);
  p.values[0]=3;
  EXPECT_EQ(gremote::ParsePhotoEdits(p.values.data(), p.values.size(), &parsed), GREMOTE_INVALID_ARGUMENT);
}
TEST(ToneV2NeutralAndAlphaAreExact) {
  gremote::PhotoEdits p; p.values[0]=2;
  const auto source=Ramp(), output=Render(p);
  EXPECT_TRUE(source.pixels == output.pixels);
}
TEST(ToneV2ExposureUsesLinearLightAndPreservesHighlightSeparation) {
  gremote::PhotoEdits p; p.values[0]=2; p.values[1]=1;
  auto output=Render(p);
  EXPECT_NEAR(output.pixels[128*4], 176, 1);
  EXPECT_TRUE(output.pixels[192*4] < output.pixels[224*4]);
  EXPECT_TRUE(output.pixels[224*4] < output.pixels[255*4]);
  p.values[3]=-1;
  output=Render(p);
  EXPECT_TRUE(output.pixels[192*4] < output.pixels[224*4]);
  EXPECT_TRUE(output.pixels[224*4] < output.pixels[255*4]);
  EXPECT_TRUE(output.pixels[224*4] < 245);
  const auto source=Ramp();
  for (int x=0; x<256; ++x) EXPECT_EQ(output.pixels[x*4+3], source.pixels[x*4+3]);
}
TEST(ToneV2BasicExtremesKeepOrderedNeutralRamps) {
  for(int control=1; control<=6; ++control) for(float sign : {-1.f,1.f}) {
    gremote::PhotoEdits p; p.values[0]=2; p.values[control]=sign*(control==1?3.f:1.f);
    auto output=Render(p);
    for(int x=1; x<256; ++x) EXPECT_TRUE(output.pixels[x*4]>=output.pixels[(x-1)*4]);
  }
}
TEST(ToneV1ExposureRemainsUnchanged) {
  gremote::PhotoEdits p; p.values[1]=1;
  const auto output=Render(p);
  EXPECT_EQ(output.pixels[64*4],128);
  EXPECT_EQ(output.pixels[128*4],255);
  EXPECT_EQ(output.pixels[192*4],255);
}

TEST(ToneV2FloatingColorsStayFiniteAtEveryControlExtreme) {
  const std::array<std::array<float,3>,7> colors = {{{0,0,0},{1,1,1},
    {.7f,.45f,.32f},{.2f,.8f,.15f},{0,0,1},{1,0,0},{0,1,0}}};
  for (int control=1; control<=10; ++control) for (float sign : {-1.f,1.f}) {
    gremote::PhotoEdits p; p.values[0]=2;
    p.values[control]=sign*(control==1?3.f:1.f);
    const auto tone=gremote::ToneV2::Build(p);
    for (const auto& color : colors) for (float channel : tone.Apply(color)) {
      EXPECT_TRUE(std::isfinite(channel));
      EXPECT_TRUE(channel>=0 && channel<=1);
    }
  }
}
TEST(ToneV2SaturationZeroKeepsLuminanceAndProducesNeutralColor) {
  gremote::PhotoEdits p; p.values[0]=2; p.values[9]=-1;
  const auto rgb=gremote::ToneV2::Build(p).Apply({.7f,.45f,.32f});
  EXPECT_NEAR(rgb[0],rgb[1],1e-6);
  EXPECT_NEAR(rgb[1],rgb[2],1e-6);
  EXPECT_TRUE(rgb[0]>.45f && rgb[0]<.7f);
}
