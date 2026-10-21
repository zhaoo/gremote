#include "m10v_spatial_accel.h"
#include <stddef.h>
#if defined(__arm__)
#include <arm_neon.h>
#endif

static uint16_t tap(uint16_t l,uint16_t m,uint16_t r){
    return (uint16_t)(((uint32_t)l+2u*m+r)>>2);
}
static __attribute__((always_inline)) inline void eight(const uint16_t *l,const uint16_t *m,const uint16_t *r,uint16_t *dst){
#if defined(__arm__)
    /* All additions widen BEFORE summing. Saturating/16-bit addition changes
     * highlights; each original pass rounds once, after the complete sum. */
    __asm__ volatile(
        "vld1.16 {d16,d17}, [%0]\n"
        "vld1.16 {d18,d19}, [%1]\n"
        "vld1.16 {d20,d21}, [%2]\n"
        "vaddl.u16 q11,d16,d20\n"
        "vaddl.u16 q12,d17,d21\n"
        "vaddw.u16 q11,q11,d18\n"
        "vaddw.u16 q12,q12,d19\n"
        "vaddw.u16 q11,q11,d18\n"
        "vaddw.u16 q12,q12,d19\n"
        "vshrn.i32 d16,q11,#2\n"
        "vshrn.i32 d17,q12,#2\n"
        "vst1.16 {d16,d17}, [%3]\n"
        : : "r"(l),"r"(m),"r"(r),"r"(dst)
        : "d16","d17","d18","d19","d20","d21","d22","d23","d24","d25","memory");
#else
    for(uint32_t i=0;i<8;++i)dst[i]=tap(l[i],m[i],r[i]);
#endif
}

int m10v_spatial_blur_u16(uint16_t *a,uint16_t *b,uint32_t capacity,
    uint32_t w,uint32_t h,uint32_t passes,uint32_t d){
    if(!a||!b||((uintptr_t)a&1)||((uintptr_t)b&1)||!w||w>384||!h||h>256||
       passes>9||d<1||d>2||capacity<w*h)return -1;
    uint32_t bytes=2*w*h;uintptr_t aa=(uintptr_t)a,bb=(uintptr_t)b;
    if(aa>UINTPTR_MAX-bytes||bb>UINTPTR_MAX-bytes||(aa<bb+bytes&&bb<aa+bytes))return -1;
    for(uint32_t pass=0;pass<passes;++pass){
        for(uint32_t y=0;y<h;++y){
            const uint16_t *src=a+y*w;uint16_t *dst=b+y*w;uint32_t x=0;
            for(;x<w&&x<d;++x)dst[x]=tap(src[0],src[x],src[x+d<w?x+d:w-1]);
            for(;x+8+d<=w;x+=8)eight(src+x-d,src+x,src+x+d,dst+x);
            for(;x<w;++x)dst[x]=tap(src[x<d?0:x-d],src[x],src[x+d<w?x+d:w-1]);
        }
        for(uint32_t y=0;y<h;++y){
            const uint16_t *top=b+(y<d?0:y-d)*w,*mid=b+y*w,*bot=b+(y+d<h?y+d:h-1)*w;
            uint16_t *dst=a+y*w;uint32_t x=0;
            for(;x+8<=w;x+=8)eight(top+x,mid+x,bot+x,dst+x);
            for(;x<w;++x)dst[x]=tap(top[x],mid[x],bot[x]);
        }
    }
    return 0;
}

int m10v_spatial_grain_work_bytes(uint32_t w,uint32_t h,uint32_t address,uint32_t *required){
    if(!required||((uintptr_t)required&3)||!w||w>6144||!h||h>4096||address>UINT32_MAX-15)return -1;
    uint32_t bytes=((w+15)&~15u)*h,padding=(-address)&15;
    if(address>UINT32_MAX-bytes-padding)return -1;
    *required=bytes+padding;return 0;
}

#if defined(__arm__)
static int stock_ram(uint32_t p,uint32_t n){return !(p&3)&&p>=0x55000000u&&p<0x80000000u&&n<=0x80000000u-p;}
static int stock_overlap(uint32_t a,uint32_t an,uint32_t b,uint32_t bn){return a<b+bn&&b<a+an;}
#endif
int m10v_spatial_stock_grain_execute(uint32_t context,const void *source,
    const void *destination,uint32_t strength,void *workspace,uint32_t capacity){
#if defined(__arm__)
    uint32_t src=(uint32_t)(uintptr_t)source,dst=(uint32_t)(uintptr_t)destination,work=(uint32_t)(uintptr_t)workspace;
    if(!stock_ram(context,16)||!stock_ram(src,32)||!stock_ram(dst,32)||!stock_ram(work,capacity)||!capacity||strength<1||strength>3)return -1;
    const uint16_t *s=(const uint16_t *)(src+16),*d=(const uint16_t *)(dst+16);
    uint32_t w=s[0],h=s[1],required=0;
    if(w<2||(w&1)||w>6144||!h||h>4096||d[0]!=w||d[1]!=h||
       s[2]<w||s[2]>16384||d[2]<w||d[2]>16384||
       m10v_spatial_grain_work_bytes(w,h,work,&required)||capacity<required)return -1;
    uint32_t input=((const uint32_t *)source)[1],output=((const uint32_t *)destination)[1];
    uint32_t input_bytes=(uint32_t)s[2]*h,output_bytes=(uint32_t)d[2]*h;
    if(!stock_ram(input,input_bytes)||!stock_ram(output,output_bytes)||
       stock_overlap(src,32,dst,32)||stock_overlap(src,32,context,16)||stock_overlap(dst,32,context,16)||
       stock_overlap(input,input_bytes,src,32)||stock_overlap(input,input_bytes,dst,32)||stock_overlap(input,input_bytes,context,16)||
       stock_overlap(output,output_bytes,src,32)||stock_overlap(output,output_bytes,dst,32)||stock_overlap(output,output_bytes,context,16)||
       stock_overlap(input,input_bytes,output,output_bytes)||
       stock_overlap(work,capacity,input,input_bytes)||stock_overlap(work,capacity,output,output_bytes)||
       stock_overlap(work,capacity,src,32)||stock_overlap(work,capacity,dst,32)||stock_overlap(work,capacity,context,16))return -1;
    typedef int (*stock_fn)(uint32_t,const void *,const void *,uint32_t,void *,uint32_t *);
    return ((stock_fn)0x5367ad3cu)(context,source,destination,strength,workspace,&capacity)?0:-4;
#else
    (void)context;(void)source;(void)destination;(void)strength;(void)workspace;(void)capacity;
    return -3;
#endif
}

static int array32(uintptr_t p){return p&&!(p&3)&&p<=UINTPTR_MAX-32;}
static int arrays_overlap(uintptr_t a,uintptr_t b){return a<b+32&&b<a+32;}
#if defined(__arm__)
static __attribute__((always_inline)) inline uint32x4_t hash4(uint32x4_t x,uint32_t y,uint32_t seed){
    x=veorq_u32(vmulq_n_u32(x,0x9e3779b9u),vdupq_n_u32(seed^y*0x85ebca6bu));
    x=veorq_u32(x,vshrq_n_u32(x,16));x=vmulq_n_u32(x,0x7feb352du);
    x=veorq_u32(x,vshrq_n_u32(x,15));x=vmulq_n_u32(x,0x846ca68bu);
    return veorq_u32(x,vshrq_n_u32(x,16));
}
static __attribute__((always_inline)) inline int32x4_t centered(uint32x4_t h){
    return vsubq_s32(vreinterpretq_s32_u32(vandq_u32(h,vdupq_n_u32(255))),vdupq_n_s32(128));
}
#else
static uint32_t hash_scalar(uint32_t x,uint32_t y,uint32_t seed){
    x=seed^x*0x9e3779b9u^y*0x85ebca6bu;x^=x>>16;x*=0x7feb352du;x^=x>>15;x*=0x846ca68bu;return x^(x>>16);
}
#endif
int m10v_spatial_grain_noise8(const uint32_t *gx,uint32_t gy,uint32_t seed,
    uint32_t size,uint32_t *hashes,int32_t *noise){
    uintptr_t x=(uintptr_t)gx,h=(uintptr_t)hashes,n=(uintptr_t)noise;
    if(size>2||!array32(x)||!array32(h)||!array32(n)||arrays_overlap(x,h)||arrays_overlap(x,n)||arrays_overlap(h,n))return -1;
#if defined(__arm__)
    for(uint32_t i=0;i<8;i+=4){
        uint32x4_t coords=vld1q_u32(gx+i),hh=hash4(coords,gy,seed);int32x4_t fine=centered(hh),base=fine;
        if(size){
            uint32_t scale=1u<<size,yy=gy>>size,dy=gy&(scale-1);
            uint32x4_t xx=vshlq_u32(coords,vdupq_n_s32(-(int32_t)size));
            int32x4_t dx=vreinterpretq_s32_u32(vandq_u32(coords,vdupq_n_u32(scale-1)));
            int32x4_t sx=vsubq_s32(vdupq_n_s32((int32_t)scale),dx);
            int32x4_t a=centered(hash4(xx,yy,seed)),b=centered(hash4(vaddq_u32(xx,vdupq_n_u32(1)),yy,seed));
            int32x4_t c=centered(hash4(xx,yy+1,seed)),d=centered(hash4(vaddq_u32(xx,vdupq_n_u32(1)),yy+1,seed));
            int32x4_t top=vaddq_s32(vmulq_s32(a,sx),vmulq_s32(b,dx));
            int32x4_t bottom=vaddq_s32(vmulq_s32(c,sx),vmulq_s32(d,dx));
            base=vshlq_s32(vaddq_s32(vmulq_n_s32(top,(int32_t)(scale-dy)),vmulq_n_s32(bottom,(int32_t)dy)),vdupq_n_s32(-(int32_t)(2*size)));
        }
        /* |fine|<=128: ceil(65536/3) multiplication is exact truncation /3.
         * Apply sign afterward, preserving C's truncation toward zero. */
        int32x4_t third=vshrq_n_s32(vmulq_n_s32(vabsq_s32(fine),21846),16);
        third=vbslq_s32(vcltq_s32(fine,vdupq_n_s32(0)),vnegq_s32(third),third);
        vst1q_u32(hashes+i,hh);vst1q_s32(noise+i,vaddq_s32(base,third));
    }
#else
    for(uint32_t i=0;i<8;++i){
        uint32_t xx=gx[i]>>size,yy=gy>>size,scale=1u<<size,dx=gx[i]&(scale-1),dy=gy&(scale-1);
        int a=(int)(hash_scalar(xx,yy,seed)&255)-128,b=(int)(hash_scalar(xx+1,yy,seed)&255)-128;
        int c=(int)(hash_scalar(xx,yy+1,seed)&255)-128,d=(int)(hash_scalar(xx+1,yy+1,seed)&255)-128;
        hashes[i]=hash_scalar(gx[i],gy,seed);
        noise[i]=((a*(int)(scale-dx)*(int)(scale-dy)+b*(int)dx*(int)(scale-dy)+c*(int)(scale-dx)*(int)dy+d*(int)dx*(int)dy)>>(2*size))+((int)(hashes[i]&255)-128)/3;
    }
#endif
    return 0;
}
