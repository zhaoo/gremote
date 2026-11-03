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

#include "gpu/spatial_plan.h"
TEST(GpuSpatialBudgetCountsAtlasPaddingAndRejectsOversizeBeforeAllocation) {
  using namespace gremote::gpu;
  const auto plan=SpatialPlan::Build(6000,4000,4096,256,3,320ull*1024*1024);
  EXPECT_EQ(plan.page_width,2048);EXPECT_EQ(plan.columns,3);EXPECT_EQ(plan.rows,2);
  EXPECT_EQ(plan.bytes,3ull*6*2048*2048*4);
  bool rejected=false;
  try{SpatialPlan::Build(20000,20000,4096,256,3,320ull*1024*1024);}catch(const std::exception&){rejected=true;}
  EXPECT_TRUE(rejected);
  rejected=false;
  try{SpatialPlan::Build(6000,4000,4096,4,3,320ull*1024*1024);}catch(const std::exception&){rejected=true;}
  EXPECT_TRUE(rejected);
}
TEST(GpuSpatialRadiusAndMaskCacheRespectSequentialHalationBloom) {
  using namespace gremote::gpu;
  PipelineInputs a;a.edits.values[17]=.4;a.edits.values[20]=.6;
  auto b=a;b.edits.values[17]=.8;
  auto dirty=DirtyMasks(a,b,false);
  EXPECT_TRUE(!dirty.halo);EXPECT_TRUE(dirty.bloom);
  b=a;b.edits.values[20]=.8;dirty=DirtyMasks(a,b,false);
  EXPECT_TRUE(!dirty.halo);EXPECT_TRUE(!dirty.bloom);
  b=a;b.edits.values[18]=.8;dirty=DirtyMasks(a,b,false);
  EXPECT_TRUE(dirty.halo);EXPECT_TRUE(dirty.bloom);
  dirty=DirtyMasks(a,a,true);EXPECT_TRUE(dirty.halo);EXPECT_TRUE(dirty.bloom);
  EXPECT_EQ(GlowRadius(6000,4000,0),12);EXPECT_EQ(GlowRadius(6000,4000,1),372);
}
