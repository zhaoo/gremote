// Run on Android only. Building this executable is not a GPU test result.
#include "test_main.h"
#include "gpu/gpu_session.h"
#include "gremote_imaging.h"

TEST(GpuSessionNeutralRoundTripAndLifecycle) {
  gremote::Image source(4,2,4);
  source.pixels={0,32,64,255, 128,160,192,173, 200,80,40,100, 255,255,255,255,
                 40,90,200,255, 20,30,40,222, 10,220,60,200, 0,0,0,0};
  const auto expected=source.pixels;
  gremote::gpu::GpuSession session(std::move(source));
  EXPECT_TRUE(session.capabilities().half_float);
  EXPECT_TRUE(session.Advance(1));
  gremote::PhotoEdits neutral; neutral.values[0]=2;
  EXPECT_TRUE(session.Render(1,neutral,nullptr,0,1,4,2));
  const auto output=session.ReadFinal();
  EXPECT_EQ(output.width,4); EXPECT_EQ(output.height,2);
  for(size_t i=0;i<expected.size();++i) EXPECT_NEAR(output.pixels[i],expected[i],1);
  EXPECT_TRUE(session.Advance(3));
  EXPECT_TRUE(!session.Render(1,neutral,nullptr,0,1,4,2));
  EXPECT_TRUE(session.Render(3,neutral,nullptr,0,1,4,2));
  session.Close(); session.Close();
  EXPECT_TRUE(!session.Advance(4));
}
TEST(GpuSessionRejectsUnsupportedDimensionsWithoutPublishingNewFrame) {
  gremote::Image source(2,2,4);
  std::fill(source.pixels.begin(),source.pixels.end(),128);
  gremote::gpu::GpuSession session(std::move(source));
  gremote::PhotoEdits neutral;
  session.Advance(1); session.Render(1,neutral,nullptr,0,1,2,2);
  bool rejected=false;
  try { session.Render(1,neutral,nullptr,0,1,0,2); }
  catch(const std::exception&) { rejected=true; }
  EXPECT_TRUE(rejected);
  EXPECT_EQ(session.ReadFinal().width,2);
}
int main() { return gremote_test::RunAll(); }
