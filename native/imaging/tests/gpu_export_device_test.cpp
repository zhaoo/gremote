#include "test_main.h"
#include "gpu/gpu_session.h"
#include "jpeg_io.h"
#include <fstream>
#include <algorithm>
#include <cstdio>
TEST(GpuExportTilesUseTheSameGraphAndGlobalSeedAsWholePreview) {
  gremote::Image source(1031,9,4);
  for(int y=0;y<source.height;++y)for(int x=0;x<source.width;++x){auto* p=source.Row(y)+x*4;p[0]=x%256;p[1]=(x*3+y*7)%256;p[2]=(x+y*17)%256;p[3]=255;}
  gremote::gpu::GpuSession session(source);gremote::PhotoEdits edits;edits.values[0]=2;edits.values[14]=.5;edits.values[17]=.4;edits.values[19]=.35;edits.values[20]=.2;edits.values[23]=.3;
  session.Advance(1);session.Render(1,edits,nullptr,0,1,1031,9);const auto preview=session.ReadFinal();
  const std::string path="/data/local/tmp/gremote-gpu-export-check.jpg";
  gremote::gpu::ExportSpec spec;spec.photo_width=spec.canvas_width=1031;spec.photo_height=spec.canvas_height=9;spec.quality=100;spec.path=path;
  session.Export(edits,nullptr,0,1,spec,nullptr);
  std::ifstream input(path,std::ios::binary);std::vector<uint8_t> jpeg((std::istreambuf_iterator<char>(input)),{});gremote::Image decoded;
  EXPECT_EQ(gremote::DecodeJpeg(jpeg.data(),jpeg.size(),1,&decoded),0);
  EXPECT_EQ(decoded.width,1031);EXPECT_EQ(decoded.height,9);
  for(size_t i=0;i<1031*9;++i)for(int c=0;c<3;++c)EXPECT_NEAR(decoded.pixels[i*3+c],preview.pixels[i*4+c],4);
  std::remove(path.c_str());
}
TEST(GpuCancelledExportDoesNotLeaveAPartialJpeg) {
  gremote::Image source(100,80,4);std::fill(source.pixels.begin(),source.pixels.end(),150);
  gremote::gpu::GpuSession session(source);gremote::PhotoEdits edits;
  gremote::gpu::ExportSpec spec;spec.photo_width=spec.canvas_width=100;spec.photo_height=spec.canvas_height=80;spec.path="/data/local/tmp/gremote-cancel-check.jpg";
  int checks=0;bool cancelled=false;
  try{session.Export(edits,nullptr,0,1,spec,nullptr,[&]{return ++checks>3;});}catch(const std::exception& e){cancelled=std::string(e.what())=="cancelled";}
  EXPECT_TRUE(cancelled);EXPECT_TRUE(!std::ifstream(spec.path).good());EXPECT_TRUE(!std::ifstream(spec.path+".part").good());
}
