#include "test_main.h"
#include "gpu/pipeline_state.h"

TEST(GpuPipelineCurveChangesKeepGeometryToneAndLutCached) {
  gremote::gpu::PipelineInputs a;
  a.source_serial=1;a.context_serial=1;a.lut_serial=12;a.strength=.6;
  a.region={100,80,0,0,100,80,1,100,80,0,0,100,80};
  auto b=a;b.edits.values[38+128]=.7;
  EXPECT_EQ(int(gremote::gpu::FirstDirty(a,b)),int(gremote::gpu::Stage::Curves));
  b.edits.values[1]=.5;
  EXPECT_EQ(int(gremote::gpu::FirstDirty(a,b)),int(gremote::gpu::Stage::Tone));
  b=a;b.lut_serial=13;
  EXPECT_EQ(int(gremote::gpu::FirstDirty(a,b)),int(gremote::gpu::Stage::Lut));
}
TEST(GpuPipelineSourceContextVersionAndResolutionRevokeAllCaches) {
  using namespace gremote::gpu;
  PipelineInputs a;
  a.source_serial=1;a.context_serial=1;
  a.region={100,80,0,0,100,80,1,100,80,0,0,100,80};
  auto check=[&](const PipelineInputs& b){EXPECT_EQ(int(FirstDirty(a,b)),int(Stage::Geometry));};
  auto b=a;b.source_serial=2;check(b);
  b=a;b.context_serial=2;check(b);
  b=a;b.edits.values[0]=2;check(b);
  b=a;b.region.target_width=60;check(b);
  b=a;b.edits.values[37]=8;check(b);
  EXPECT_EQ(int(FirstDirty(a,a)),int(Stage::Clean));
  b=a;b.edits.values[17]=.5;
  EXPECT_EQ(int(FirstDirty(a,b)),int(Stage::Optics));
  b=a;b.edits.values[29]=12;
  EXPECT_EQ(int(FirstDirty(a,b)),int(Stage::Texture));
}
