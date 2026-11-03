#pragma once
#include "photo_edits.h"
#include <cstdint>
#include <tuple>

namespace gremote::gpu {
enum class Stage { Geometry, Tone, Lut, Curves, Optics, Texture, Clean };
struct GeometryRegion {
  int source_width=0,source_height=0,source_x=0,source_y=0,source_region_width=0,source_region_height=0;
  int exif=1,output_width=0,output_height=0,output_x=0,output_y=0,target_width=0,target_height=0;
  bool operator==(const GeometryRegion& b) const {
    return std::tie(source_width,source_height,source_x,source_y,source_region_width,source_region_height,
      exif,output_width,output_height,output_x,output_y,target_width,target_height)==
      std::tie(b.source_width,b.source_height,b.source_x,b.source_y,b.source_region_width,b.source_region_height,
      b.exif,b.output_width,b.output_height,b.output_x,b.output_y,b.target_width,b.target_height);
  }
};
struct PipelineInputs {
  uint64_t source_serial=0,context_serial=0,lut_serial=0;
  GeometryRegion region;
  PhotoEdits edits;
  float strength=1;
};
inline Stage FirstDirty(const PipelineInputs& a,const PipelineInputs& b){
  const auto& x=a.edits.values;const auto& y=b.edits.values;
  if(a.source_serial!=b.source_serial||a.context_serial!=b.context_serial||!(a.region==b.region)||x[0]!=y[0])return Stage::Geometry;
  for(int i=30;i<38;++i)if(x[i]!=y[i])return Stage::Geometry;
  for(int i=1;i<=10;++i)if(x[i]!=y[i])return Stage::Tone;
  if(a.lut_serial!=b.lut_serial||a.strength!=b.strength)return Stage::Lut;
  for(int i=38;i<kPhotoEditCount;++i)if(x[i]!=y[i])return Stage::Curves;
  for(int i=17;i<=22;++i)if(x[i]!=y[i])return Stage::Optics;
  for(int i=11;i<=16;++i)if(x[i]!=y[i])return Stage::Texture;
  for(int i=23;i<=29;++i)if(x[i]!=y[i])return Stage::Texture;
  return Stage::Clean;
}
}  // namespace gremote::gpu
