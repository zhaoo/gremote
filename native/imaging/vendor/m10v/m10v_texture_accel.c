#include "m10v_texture_accel.h"
#if defined(__arm__)
#include <arm_neon.h>
#endif
/* Clang's fixed four-lane vectors map directly to NEON on ARMv7; identical
 * integer expressions execute as host vectors for the differential oracle. */
typedef int32_t V __attribute__((ext_vector_type(4)));
static V sel(V mask,V a,V b){return (mask&a)|(~mask&b);}
static V clamp(V v){v=sel(v<0,(V){0,0,0,0},v);return sel(v>255,(V){255,255,255,255},v);}
static V round16(V v){V sign=v>>31,a=(v^sign)-sign;return (((a+32768)>>16)^sign)-sign;}
/* Exact floor /255 for nonnegative v<=65534, including LUT sum+127. */
static V div255(V v){return (v+1+(v>>8))>>8;}
/* Denominators are3*2^18 and3*2^14. Abs then shift then /3 is
 * exact truncation; quotient input<=105 or8. Reciprocal21846 is exact here. */
static V truncgrain(V v,int shift){V sign=v>>31,a=(v^sign)-sign;a=a>>shift;return ((((a*21846)>>16)^sign)-sign);}
static __attribute__((always_inline)) inline void gather3(const uint8_t *lut,V ix,V out[3]){
#if defined(__arm__)
 uint8x8x3_t v={{vdup_n_u8(0),vdup_n_u8(0),vdup_n_u8(0)}};
 v=vld3_lane_u8(lut+3*ix[0],v,0);v=vld3_lane_u8(lut+3*ix[1],v,1);
 v=vld3_lane_u8(lut+3*ix[2],v,2);v=vld3_lane_u8(lut+3*ix[3],v,3);
 out[0]=(V)vmovl_u16(vget_low_u16(vmovl_u8(v.val[0])));
 out[1]=(V)vmovl_u16(vget_low_u16(vmovl_u8(v.val[1])));
 out[2]=(V)vmovl_u16(vget_low_u16(vmovl_u8(v.val[2])));
#else
 for(unsigned c=0;c<3;c++)for(unsigned k=0;k<4;k++)out[c][k]=lut[3*ix[k]+c];
#endif
}
static __attribute__((noinline)) int texture_block_core(uint8_t *y,uint8_t *uv,const uint8_t *lut,const m10v_texture_block_params *p,void *cache,uint32_t chroma_enabled){
 if(!y||!uv||!p||((uintptr_t)p&3)||p->grain_q8>1024||((uintptr_t)cache&3))return -1;
 for(unsigned i=0;i<8;i++)if(p->noise[i]<-170||p->noise[i]>169)return -1;
 int hits=0;
 V mapped[2][3];
 for(unsigned half=0;half<2;half++){
  V yy,cb,cr,light,hash,noise;
#if defined(__arm__)
  uint8x8_t y8=vld1_u8(y),uv8=vld1_u8(uv),l8=vld1_u8(p->light);
  uint8x8_t cbi={0,0,2,2,4,4,6,6},cri={1,1,3,3,5,5,7,7};
  uint16x8_t y16=vmovl_u8(y8),cb16=vmovl_u8(vtbl1_u8(uv8,cbi)),cr16=vmovl_u8(vtbl1_u8(uv8,cri)),l16=vmovl_u8(l8);
  yy=(V)vmovl_u16(half?vget_high_u16(y16):vget_low_u16(y16));
  cb=(V)vmovl_u16(half?vget_high_u16(cb16):vget_low_u16(cb16));cb-=128;
  cr=(V)vmovl_u16(half?vget_high_u16(cr16):vget_low_u16(cr16));cr-=128;
  light=(V)vmovl_u16(half?vget_high_u16(l16):vget_low_u16(l16));
  hash=(V)vld1q_u32(p->hashes+half*4);noise=(V)vld1q_s32(p->noise+half*4);
#else
  for(unsigned k=0;k<4;k++){unsigned i=half*4+k;yy[k]=y[i];cb[k]=(int)uv[i&~1u]-128;cr[k]=(int)uv[(i&~1u)+1]-128;light[k]=p->light[i];hash[k]=(int32_t)p->hashes[i];noise[k]=p->noise[i];}
#endif
  V rgb[3]={clamp(yy+round16(cr*91881)),clamp(yy-round16(cb*22554+cr*46802)),clamp(yy+round16(cb*116130))};
  V original[3]={rgb[0],rgb[1],rgb[2]};
  const int t[3]={256,112,36};V f[3],pos[3];
  for(unsigned c=0;c<3;c++)rgb[c]=clamp(rgb[c]+((light*t[c]*(255-rgb[c]))>>16));
  if(lut){
  V keys=rgb[0]|(rgb[1]<<8)|(rgb[2]<<16);uint32_t *slots[4];int halfhits=0;
  if(cache){
   for(unsigned k=0;k<4;k++){uint32_t key=(uint32_t)keys[k];slots[k]=(uint32_t *)cache+((key*0x9e3779b9u)>>19)*2;
    if(slots[k][0]==(key|0x01000000u))++halfhits;}
   hits+=halfhits;
  }
  if(halfhits==4){
   for(unsigned k=0;k<4;k++){uint32_t value=slots[k][1];mapped[half][0][k]=value&255;mapped[half][1][k]=(value>>8)&255;mapped[half][2][k]=(value>>16)&255;}
  }else{
  for(unsigned c=0;c<3;c++){V q=rgb[c]*14;pos[c]=div255(q);pos[c]=sel(pos[c]>13,(V){13,13,13,13},pos[c]);f[c]=q-pos[c]*255;}
  V step[3]={{225,225,225,225},{15,15,15,15},{1,1,1,1}};
  const unsigned aa[3]={0,0,1},bb[3]={1,2,2};
  for(unsigned j=0;j<3;j++){unsigned a=aa[j],b=bb[j];V mask=f[b]>f[a],fa=f[a],sa=step[a];f[a]=sel(mask,f[b],fa);f[b]=sel(mask,fa,f[b]);step[a]=sel(mask,step[b],sa);step[b]=sel(mask,sa,step[b]);}
  V ix=pos[0]*225+pos[1]*15+pos[2],weights[4]={255-f[0],f[0]-f[1],f[1]-f[2],f[2]};
  V indices[4]={ix,ix+step[0],ix+step[0]+step[1],ix+241};
  V total[3]={{127,127,127,127},{127,127,127,127},{127,127,127,127}};
  #pragma clang loop unroll(full)
  for(unsigned j=0;j<4;j++){V g[3];gather3(lut,indices[j],g);total[0]+=g[0]*weights[j];total[1]+=g[1]*weights[j];total[2]+=g[2]*weights[j];}
  for(unsigned c=0;c<3;c++)mapped[half][c]=div255(total[c]);
  if(cache)for(unsigned k=0;k<4;k++){
   slots[k][0]=(uint32_t)keys[k]|0x01000000u;
   slots[k][1]=(uint32_t)mapped[half][0][k]|((uint32_t)mapped[half][1][k]<<8)|((uint32_t)mapped[half][2][k]<<16);
  }
  }
  }else for(unsigned c=0;c<3;c++)mapped[half][c]=rgb[c];
  if(p->grain_q8){
  V lum=(mapped[half][0]*54+mapped[half][1]*183+mapped[half][2]*19)>>8;
  V weight=32+sel(lum<128,lum,255-lum);V delta=truncgrain(noise*(int)p->grain_q8*weight,18);
  for(unsigned c=0;c<3;c++){V fine=((hash>>(c*8))&255)-128;mapped[half][c]=clamp(mapped[half][c]+delta+truncgrain(fine*(int)p->grain_q8,14));}
  }
  if(!lut)for(unsigned c=0;c<3;c++)mapped[half][c]-=original[c];
  V out=round16(mapped[half][0]*19595+mapped[half][1]*38470+mapped[half][2]*7471);
  out=clamp(lut?out:yy+out);
  for(unsigned k=0;k<4;k++)y[half*4+k]=(uint8_t)out[k];
 }
 if(!lut&&!chroma_enabled)return hits;
 V pair[3];
 for(unsigned c=0;c<3;c++){
  V even=__builtin_shufflevector(mapped[0][c],mapped[1][c],0,2,4,6);
  V odd=__builtin_shufflevector(mapped[0][c],mapped[1][c],1,3,5,7);pair[c]=even+odd;
 }
 V cb=pair[0]*-11059-pair[1]*21709+pair[2]*32768;
 V cr=pair[0]*32768-pair[1]*27439-pair[2]*5329;
 V sign=cb>>31,a=(cb^sign)-sign;cb=((((a+65536)>>17)^sign)-sign);
 sign=cr>>31;a=(cr^sign)-sign;cr=((((a+65536)>>17)^sign)-sign);
 V basecb={128,128,128,128},basecr={128,128,128,128};
 if(!lut)for(unsigned k=0;k<4;k++){basecb[k]=uv[k*2];basecr[k]=uv[k*2+1];}
 cb=clamp(basecb+cb);cr=clamp(basecr+cr);
 for(unsigned k=0;k<4;k++){uv[k*2]=(uint8_t)cb[k];uv[k*2+1]=(uint8_t)cr[k];}
 return hits;
}
int m10v_texture_block8_cached(uint8_t *y,uint8_t *uv,const uint8_t *lut,const m10v_texture_block_params *p,void *cache){
 if(!lut)return -1;
 return texture_block_core(y,uv,lut,p,cache,1);
}
int m10v_texture_effects_block8(uint8_t *y,uint8_t *uv,const m10v_texture_block_params *p,uint32_t chroma_enabled){
 if(chroma_enabled>1)return -1;
 return texture_block_core(y,uv,0,p,0,chroma_enabled);
}
int m10v_texture_block8(uint8_t *y,uint8_t *uv,const uint8_t *lut,const m10v_texture_block_params *p){
 return m10v_texture_block8_cached(y,uv,lut,p,0);
}
