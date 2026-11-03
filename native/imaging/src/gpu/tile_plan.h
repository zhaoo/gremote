#pragma once
#include <vector>
#include <algorithm>
#include <stdexcept>
#include <cstdint>
namespace gremote::gpu {
struct Rect {int x=0,y=0,width=0,height=0;};
inline Rect Intersect(Rect a,Rect b){int x=std::max(a.x,b.x),y=std::max(a.y,b.y);return {x,y,std::max(0,std::min(a.x+a.width,b.x+b.width)-x),std::max(0,std::min(a.y+a.height,b.y+b.height)-y)};}
struct TilePlan {
  static std::vector<Rect> Build(int w,int h,int edge,int band){
    if(w<=0||h<=0||w>65535||h>65535||int64_t(w)*h>400000000||edge<1||band<1)throw std::runtime_error("gpuInvalidExportSize");
    std::vector<Rect> tiles;
    for(int y=0;y<h;y+=band)for(int x=0;x<w;x+=edge)tiles.push_back({x,y,std::min(edge,w-x),std::min(band,h-y)});
    return tiles;
  }
};
}
