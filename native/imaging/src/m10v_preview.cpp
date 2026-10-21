#include "m10v_preview.h"
#include <algorithm>
#include <cstring>
#include <new>
#include <vector>
extern "C" {
#include "m10v_library.h"
}

namespace {
uint8_t Clamp(int v){return uint8_t(std::max(0,std::min(255,v)));}
int KeepInMemory(void*,const m10v_library_state*){return 0;}
bool Cancelled(const volatile int32_t* flag){return flag&&*flag;}
bool Overlaps(const void* a,const void* b,size_t size){
 const auto x=reinterpret_cast<uintptr_t>(a),y=reinterpret_cast<uintptr_t>(b);
 return x>UINTPTR_MAX-size||y>UINTPTR_MAX-size||(x<y+size&&y<x+size);
}
int Render(const uint8_t* rgba,uint32_t w,uint32_t h,uint32_t pitch,
 const uint8_t* r,uint32_t n,uint32_t stage,uint8_t* out,const volatile int32_t* cancel){
 if(!rgba||!out||!r||n!=16||!w||!h||w>960||h>960||pitch<w*4||pitch>960*4+4096||stage>1||r[14]||r[15])return GREMOTE_INVALID_ARGUMENT;
 if(Overlaps(rgba,out,size_t(pitch)*h))return GREMOTE_INVALID_ARGUMENT;
 if(Cancelled(cancel))return GREMOTE_CANCELLED;
 const uint32_t film=r[0]|uint32_t(r[1])<<8;
 if(!M10V_BUILTIN(film)||r[2]>3||r[3]>2||r[4]>8||r[5]>8||r[6]>8||r[7]>3||r[8]>8||r[9]>5||r[10]>8||r[11]>1||r[12]>2||r[13]>3)return GREMOTE_INVALID_ARGUMENT;
 if((film!=33&&film!=67&&r[4])||(film!=67&&film!=68&&r[12])||(film==67&&r[12]>1)||(film!=289&&r[13])||(film==289&&(r[2]||r[8])))return GREMOTE_INVALID_ARGUMENT;
 m10v_library_state state;m10v_library_init(&state);
 if(m10v_library_select(&state,0,film,KeepInMemory,nullptr)||m10v_library_texture(&state,0,r[2],0,KeepInMemory,nullptr))return GREMOTE_INVALID_ARGUMENT;
 // Only films advertising halation may enter its native setter. In particular
 // 5207 and RED intentionally reject that API, even for a zero-gain request.
 if((film==33||film==67)&&m10v_library_halation(&state,0,r[4],r[5],r[6],r[7],KeepInMemory,nullptr))return GREMOTE_INVALID_ARGUMENT;
 const uint8_t effects[5]={r[3],r[8],r[9],r[10],r[11]};
 for(uint32_t i=0;i<5;i++)if(m10v_library_effects(&state,0,i,effects[i],KeepInMemory,nullptr))return GREMOTE_INVALID_ARGUMENT;
 if((film==67||film==68)&&m10v_library_effects(&state,0,6,r[12],KeepInMemory,nullptr))return GREMOTE_INVALID_ARGUMENT;
 if(film==289&&m10v_library_effects(&state,0,7,r[13],KeepInMemory,nullptr))return GREMOTE_INVALID_ARGUMENT;
 const uint32_t stride=std::max(2u,(w+1)&~1u),size=stride*h;
 std::vector<uint8_t> y(size),uv(size);
 for(uint32_t row=0;row<h;row++){
  if(Cancelled(cancel))return GREMOTE_CANCELLED;
  for(uint32_t x=0;x<stride;x+=2){
   const auto a=rgba+size_t(row)*pitch+std::min(x,w-1)*4;
   const auto b=rgba+size_t(row)*pitch+std::min(x+1,w-1)*4;
   y[row*stride+x]=Clamp((77*a[0]+150*a[1]+29*a[2]+128)>>8);
   y[row*stride+x+1]=Clamp((77*b[0]+150*b[1]+29*b[2]+128)>>8);
   const int red=(int(a[0])+b[0]+1)/2,green=(int(a[1])+b[1]+1)/2,blue=(int(a[2])+b[2]+1)/2;
   uv[row*stride+x]=Clamp(128+((-43*red-85*green+128*blue+128)>>8));
   uv[row*stride+x+1]=Clamp(128+((128*red-107*green-21*blue+128)>>8));
  }
 }
 m10v_library_image image{y.data(),uv.data(),size,size,stride,h,stride};
 std::vector<uint32_t> scratch((6*384*256+65536)/4);
 const uint32_t completed=stage==1?(M10V_NATIVE_GRAIN|M10V_NATIVE_SOFT|M10V_NATIVE_HALO|M10V_NATIVE_LEAK):0;
 if(m10v_library_render_native(&image,&state,0,nullptr,123,reinterpret_cast<uint8_t*>(scratch.data()),uint32_t(scratch.size()*4),completed))return GREMOTE_INVALID_ARGUMENT;
 if(Cancelled(cancel))return GREMOTE_CANCELLED;
 for(uint32_t row=0;row<h;row++)for(uint32_t x=0;x<w;x++){
  const uint32_t pair=row*stride+(x&~1u);const int cb=int(uv[pair])-128,cr=int(uv[pair+1])-128,l=y[row*stride+x];
  auto p=out+size_t(row)*pitch+x*4;
  p[0]=Clamp(l+((359*cr+128)>>8));p[1]=Clamp(l-((88*cb+183*cr+128)>>8));p[2]=Clamp(l+((454*cb+128)>>8));p[3]=rgba[size_t(row)*pitch+x*4+3];
 }
 return GREMOTE_OK;
}
}

extern "C" int32_t gr_film_preview_v1(const uint8_t* rgba,uint32_t width,
 uint32_t height,uint32_t pitch,const uint8_t* recipe,uint32_t bytes,
 uint32_t stages,uint8_t* out,const volatile int32_t* cancel){
 try{return Render(rgba,width,height,pitch,recipe,bytes,stages,out,cancel);}
 catch(const std::bad_alloc&){return GREMOTE_OUT_OF_MEMORY;}
 catch(...){return GREMOTE_INVALID_ARGUMENT;}
}
