#include "input_color.h"
#include "skcms.h"
#include <array>
#include <cstring>
namespace gremote {
bool ReadJpegIcc(const uint8_t* jpeg,size_t n,std::vector<uint8_t>* out){
  if(!out||!jpeg||n<4||jpeg[0]!=255||jpeg[1]!=216)return false;
  out->clear();std::array<std::vector<uint8_t>,255> parts;int count=0,seen=0;size_t total=0,pos=2;
  while(pos+1<n){
    if(jpeg[pos++]!=255)return false;
    while(pos<n&&jpeg[pos]==255)++pos;if(pos>=n)return false;const int marker=jpeg[pos++];
    if(marker==218||marker==217)break;
    if(marker==1||(marker>=208&&marker<=215))continue;
    if(pos+2>n)return false;size_t size=(size_t(jpeg[pos])<<8)|jpeg[pos+1];if(size<2||size>n-pos)return false;
    const auto* data=jpeg+pos+2;const size_t bytes=size-2;
    if(marker==226&&bytes>=12&&std::memcmp(data,"ICC_PROFILE\0",12)==0){
      if(bytes<14)return false;const int index=data[12],expected=data[13];
      if(!index||!expected||index>expected||(count&&count!=expected)||!parts[index-1].empty()||bytes==14)return false;
      count=expected;total+=bytes-14;if(total>4*1024*1024)return false;
      parts[index-1].assign(data+14,data+bytes);++seen;
    }
    pos+=size;
  }
  if(seen!=count)return false;for(int i=0;i<count;++i)out->insert(out->end(),parts[i].begin(),parts[i].end());return true;
}
bool NormalizeToSrgb(Image* rgb,const std::vector<uint8_t>& icc,bool adobe){
  if(!rgb||rgb->channels!=3)return false;
  if(icc.empty()&&!adobe)return true;
  skcms_ICCProfile profile{};
  if(!icc.empty()){if(!skcms_Parse(icc.data(),icc.size(),&profile))return false;}
  else{
    skcms_Init(&profile);
    skcms_TransferFunction gamma={2.19921875f,1,0,0,0,0,0};
    skcms_SetTransferFunction(&profile,&gamma);
    skcms_Matrix3x3 matrix;
    if(!skcms_PrimariesToXYZD50(.64f,.33f,.21f,.71f,.15f,.06f,.3127f,.3290f,&matrix))return false;
    skcms_SetXYZD50(&profile,&matrix);
  }
  return skcms_Transform(rgb->pixels.data(),skcms_PixelFormat_RGB_888,skcms_AlphaFormat_Opaque,&profile,
    rgb->pixels.data(),skcms_PixelFormat_RGB_888,skcms_AlphaFormat_Opaque,skcms_sRGB_profile(),size_t(rgb->width)*rgb->height);
}
}
