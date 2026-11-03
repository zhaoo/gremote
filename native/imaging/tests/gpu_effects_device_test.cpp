#include "test_main.h"
#include "gpu/gpu_session.h"
#include "gremote_imaging.h"
TEST(GpuLegacyEffectsMatchReferenceAtEdgesAndFixedSeed) {
  gremote::Image source(129,7,4);
  for(int y=0;y<source.height;++y)for(int x=0;x<source.width;++x){auto* p=source.Row(y)+x*4;p[0]=(x*7+y*3)%256;p[1]=(x*5+y*11)%256;p[2]=(x*3+y*7)%256;p[3]=180;}
  gremote::gpu::GpuSession session(source);uint64_t generation=0;
  for(int effect:{11,14,17,20,23,27,28,-1}){
    gremote::PhotoEdits edits;if(effect<0){for(int i:{11,14,17,20,23,27,28})edits.values[i]=.6;}else edits.values[effect]=.8;
    edits.values[29]=1234;edits.values[19]=.4;edits.values[22]=.4;
    gremote::Image cpu;EXPECT_EQ(gremote::RenderPhoto(source,edits,nullptr,1,129,7,&cpu),GREMOTE_OK);
    session.Advance(++generation);session.Render(generation,edits,nullptr,0,1,129,7);const auto first=session.ReadFinal();
    for(size_t i=0;i<cpu.pixels.size();++i)EXPECT_NEAR(first.pixels[i],cpu.pixels[i],1);
    session.Advance(++generation);session.Render(generation,edits,nullptr,0,1,129,7);const auto second=session.ReadFinal();
    EXPECT_TRUE(first.pixels==second.pixels);
  }
}
TEST(GpuOpticalGainUsesCachedMaskAndCurveInvalidatesIt) {
  gremote::Image source(129,3,4);std::fill(source.pixels.begin(),source.pixels.end(),255);
  gremote::gpu::GpuSession session(source);gremote::PhotoEdits e;e.values[0]=2;e.values[17]=.3;
  session.Advance(1);session.Render(1,e,nullptr,0,1,129,3);auto a=session.stage_counts();
  e.values[17]=.8;session.Advance(2);session.Render(2,e,nullptr,0,1,129,3);auto b=session.stage_counts();EXPECT_EQ(a[4],b[4]);
  e.values[38+255]=.5;session.Advance(3);session.Render(3,e,nullptr,0,1,129,3);auto c=session.stage_counts();EXPECT_TRUE(c[4]>b[4]);
}
