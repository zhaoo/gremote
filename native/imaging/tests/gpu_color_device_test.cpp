#include "test_main.h"
#include "gpu/gpu_session.h"
#include "gremote_imaging.h"
#include <algorithm>
#include <string>

TEST(GpuColorVersionsMatchReferenceAndCurveChangesReuseUpstream) {
  gremote::Image source(4,1,4);
  source.pixels={64,64,64,255,128,128,128,173,192,120,80,128,224,224,224,99};
  gremote::gpu::GpuSession session(source);
  for(int version:{1,2}) {
    gremote::PhotoEdits edits;edits.values[0]=float(version);edits.values[1]=1;
    const uint64_t generation=uint64_t(version);
    session.Advance(generation);session.Render(generation,edits,nullptr,0,1,4,1);
    const auto out=session.ReadFinal();gremote::Image cpu;
    EXPECT_EQ(gremote::RenderPhoto(source,edits,nullptr,1,4,1,&cpu),GREMOTE_OK);
    for(size_t i=0;i<out.pixels.size();++i)EXPECT_NEAR(out.pixels[i],cpu.pixels[i],1);
  }
  auto edits=gremote::PhotoEdits();edits.values[0]=2;edits.values[1]=1;
  const auto counts=session.stage_counts();
  edits.values[38+128]=.7;
  session.Advance(3);session.Render(3,edits,nullptr,0,1,4,1);
  const auto next=session.stage_counts();
  EXPECT_EQ(next[0],counts[0]);EXPECT_EQ(next[1],counts[1]);EXPECT_TRUE(next[3]>counts[3]);
}
TEST(GpuColorNonAffineCubeUsesExistingTetrahedralContract) {
  const std::string cube="LUT_3D_SIZE 2\n0 0 0\n0 0 0\n0 0 0\n0 0 0\n0 0 0\n0 0 0\n0 0 0\n1 1 1\n";
  gremote::Image source(1,1,4);source.pixels={51,102,153,173};
  gremote::gpu::GpuSession session(source);gremote::PhotoEdits edits;
  session.Advance(1);
  session.Render(1,edits,reinterpret_cast<const uint8_t*>(cube.data()),cube.size(),1,1,1);
  const auto out=session.ReadFinal();
  EXPECT_NEAR(out.pixels[0],51,1);EXPECT_NEAR(out.pixels[1],51,1);EXPECT_NEAR(out.pixels[2],51,1);EXPECT_EQ(out.pixels[3],173);
}

TEST(GpuPreparedCubeDomainAndBadLutPreserveValidOutput) {
  const std::string cube="LUT_3D_SIZE 2\nDOMAIN_MIN 0.1 0.2 0.3\nDOMAIN_MAX 0.9 0.8 0.7\n0 0 0\n0 0 0\n0 0 0\n0 0 0\n0 0 0\n0 0 0\n0 0 0\n1 1 1\n";
  gremote::Image source(1,1,4);source.pixels={153,153,102,200};
  gremote::gpu::GpuSession session(source);gremote::PhotoEdits edits;
  session.PrepareLut("domain",reinterpret_cast<const uint8_t*>(cube.data()),cube.size());
  bool rejected=false;
  try { session.PrepareLut("bad",reinterpret_cast<const uint8_t*>("invalid"),7); }
  catch(const std::exception&){rejected=true;}
  EXPECT_TRUE(rejected);
  session.Advance(1);session.RenderPrepared(1,edits,"domain",1,1,1);
  const auto out=session.ReadFinal();
  for(int c=0;c<3;++c)EXPECT_NEAR(out.pixels[c],64,1);
  EXPECT_EQ(out.pixels[3],200);
}
