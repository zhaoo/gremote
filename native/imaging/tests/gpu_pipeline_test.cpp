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

#include "gpu/tile_plan.h"
TEST(GpuExportTilesCoverPanoramasExactlyAndIntersectPhotoGlobally) {
  using namespace gremote::gpu;
  const auto tiles=TilePlan::Build(18000,2200,1024,64);
  uint64_t area=0;
  for(const auto& tile:tiles){EXPECT_TRUE(tile.width<=1024&&tile.height<=64);area+=uint64_t(tile.width)*tile.height;}
  EXPECT_EQ(area,18000ull*2200);
  const auto rect=Intersect({0,0,512,64},{30,40,6000,4000});
  EXPECT_EQ(rect.x,30);EXPECT_EQ(rect.y,40);EXPECT_EQ(rect.width,482);EXPECT_EQ(rect.height,24);
  bool rejected=false;try{TilePlan::Build(65536,1,1024,64);}catch(const std::exception&){rejected=true;}EXPECT_TRUE(rejected);
}

#include "input_color.h"
TEST(InputColorRejectsIncompleteIccAndConvertsAdobeWithoutTintingNeutral) {
  std::vector<uint8_t> jpeg={255,216,255,226,0,17,'I','C','C','_','P','R','O','F','I','L','E',0,1,2,0,255,218};
  std::vector<uint8_t> profile;EXPECT_TRUE(!gremote::ReadJpegIcc(jpeg.data(),jpeg.size(),&profile));
  gremote::Image input(2,1,3);input.pixels={128,128,128,160,100,80};
  EXPECT_TRUE(gremote::NormalizeToSrgb(&input,{},true));
  EXPECT_NEAR(input.pixels[0],input.pixels[1],1);EXPECT_NEAR(input.pixels[1],input.pixels[2],1);
  EXPECT_TRUE(input.pixels[3]>160);EXPECT_TRUE(input.pixels[4]<101);
  EXPECT_TRUE(!gremote::NormalizeToSrgb(&input,{1,2,3},false));
}
