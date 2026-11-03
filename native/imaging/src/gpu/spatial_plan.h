#pragma once
#include "pipeline_state.h"
#include <algorithm>
#include <cmath>
#include <stdexcept>
namespace gremote::gpu {
// Check padded GPU storage before allocating any full-image scalar mask.
struct SpatialPlan {
  int width,height,page_width,page_height,columns,rows;
  uint64_t bytes;
  static SpatialPlan Build(int w,int h,int maximum,int layers,int masks,uint64_t budget) {
    if(w<=0||h<=0||w>65535||h>65535||maximum<1||masks<1)throw std::runtime_error("gpuInvalidSpatialSize");
    const int pw=std::min({w,maximum,2048}),ph=std::min({h,maximum,2048});
    const int columns=(w+pw-1)/pw,rows=(h+ph-1)/ph;
    const uint64_t bytes=uint64_t(pw)*ph*columns*rows*4*masks;
    if(int64_t(columns)*rows>layers||bytes>budget)throw std::runtime_error("gpuSpatialMemoryLimit");
    return {w,h,pw,ph,columns,rows,bytes};
  }
};
inline int GlowRadius(int w,int h,float radius){return std::max(1,int(std::lround(std::max(w,h)*(.002f+.06f*radius))));}
struct MaskDirty { bool halo,bloom; };
inline MaskDirty DirtyMasks(const PipelineInputs& a,const PipelineInputs& b,bool upstream){
  const auto& x=a.edits.values;const auto& y=b.edits.values;
  const bool halo=upstream||x[0]!=y[0]||x[18]!=y[18]||x[19]!=y[19]||(x[17]==0&&y[17]!=0);
  const bool bloom=upstream||x[0]!=y[0]||x[21]!=y[21]||x[22]!=y[22]||(x[20]==0&&y[20]!=0)||
    ((x[17]!=0||y[17]!=0)&&(halo||x[17]!=y[17]));
  return {halo,bloom};
}
}
