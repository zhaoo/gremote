/* M10V camera implementation. Reference data attribution in 5207-reference.json.
 * Input is an assumed display-referred domain, NOT recovered scene radiance. */
#include "film_5207.h"
#ifndef M10V_TEXTURE_NEON
#define M10V_TEXTURE_NEON 0
#endif
#if M10V_FILM_COLOR_CANDIDATE
static const uint8_t m10v_5207_lut[3375][3] __attribute__((used));
#endif
#include "film_5207_data.h"
#include "film_harman.h"
#include "m10v_color_cache.h"
#if M10V_TEXTURE_NEON
#include "m10v_texture_accel.h"
#if !M10V_SPATIAL_NEON
#error Texture blocks require the exact grain batch implementation
#endif
#endif
#if M10V_SPATIAL_NEON
#include "m10v_spatial_accel.h"
#endif
#if M10V_FILM_COLOR_CANDIDATE
#include "m10v_film_color_candidates.h"
/* Retain the base payload for existing readback/provenance validation. */
#define m10v_5207_lut m10v_5207_candidate_lut
#endif

static uint8_t clip(int x){return (uint8_t)(x<0?0:x>255?255:x);}
static int roundq(int x,int bits){int h=1<<(bits-1);return x>=0?(x+h)>>bits:-((-x+h)>>bits);}
static uint32_t random32(uint32_t x){x^=x>>16;x*=0x7feb352du;x^=x>>15;x*=0x846ca68bu;return x^(x>>16);}
void m10v_5207_rgb(const uint8_t rgb[3],uint8_t out[3]){
    /* Exact tetrahedral barycentric weights. Sorting the fractions with
     * their axis steps keeps the same four vertices as the former loops.
     * Expanding telescoping differences yields nonnegative weights summing
     * to 255, so totals stay in [0,65025]; +127 and /255 are unchanged.
     * Scalars avoid per-pixel stack arrays and nested loops on ARM -Os. */
    uint32_t q0=(uint32_t)rgb[0]*14,q1=(uint32_t)rgb[1]*14,q2=(uint32_t)rgb[2]*14;
    uint32_t p0=q0/255,p1=q1/255,p2=q2/255;
    if(p0>13)p0=13;if(p1>13)p1=13;if(p2>13)p2=13;
    uint32_t f0=q0-p0*255,f1=q1-p1*255,f2=q2-p2*255;
    uint32_t s0=225,s1=15,s2=1,t;
    if(f1>f0){t=f0;f0=f1;f1=t;t=s0;s0=s1;s1=t;}
    if(f2>f0){t=f0;f0=f2;f2=t;t=s0;s0=s2;s2=t;}
    if(f2>f1){t=f1;f1=f2;f2=t;t=s1;s1=s2;s2=t;}
    uint32_t index=(p0*15+p1)*15+p2;
    const uint8_t *a=m10v_5207_lut[index],*b=m10v_5207_lut[index+s0],*c=m10v_5207_lut[index+s0+s1],*d=m10v_5207_lut[index+(225+15+1)];
    uint32_t w0=255-f0,w1=f0-f1,w2=f1-f2;
    out[0]=clip((int)((w0*a[0]+w1*b[0]+w2*c[0]+f2*d[0]+127)/255));
    out[1]=clip((int)((w0*a[1]+w1*b[1]+w2*c[1]+f2*d[1]+127)/255));
    out[2]=clip((int)((w0*a[2]+w1*b[2]+w2*c[2]+f2*d[2]+127)/255));
}
static int noise(uint32_t x,uint32_t y,uint32_t seed,uint32_t size){
    uint32_t scale=1u<<size,xx=x>>size,yy=y>>size;
    uint32_t dx=x&(scale-1),dy=y&(scale-1);
    int a=(int)(random32(seed^xx*0x9e3779b9u^yy*0x85ebca6bu)&255)-128;
    int b=(int)(random32(seed^(xx+1)*0x9e3779b9u^yy*0x85ebca6bu)&255)-128;
    int c=(int)(random32(seed^xx*0x9e3779b9u^(yy+1)*0x85ebca6bu)&255)-128;
    int d=(int)(random32(seed^(xx+1)*0x9e3779b9u^(yy+1)*0x85ebca6bu)&255)-128;
    return (a*(int)(scale-dx)*(int)(scale-dy)+b*(int)dx*(int)(scale-dy)+c*(int)(scale-dx)*(int)dy+d*(int)dx*(int)dy)>>(size*2);
}
/* One invocation owns its lattice cache; concurrent captures share no state.
 * Bilinear cells repeat across adjacent full-resolution pixels. Retain their
 * four corners rather than hashing all four again for every pixel. */
typedef struct { uint32_t x,y; int a,b,c,d; } grain_lattice;
static int grain_noise(uint32_t x,uint32_t y,uint32_t seed,uint32_t size,uint32_t hash,grain_lattice *cache){
    if(!size)return (int)(hash&255)-128;
    uint32_t xx=x>>size,yy=y>>size,scale=1u<<size;
    if(cache->x!=xx||cache->y!=yy){
        if(cache->y==yy&&cache->x+1==xx){cache->a=cache->b;cache->c=cache->d;}
        else{
            cache->a=(int)(random32(seed^xx*0x9e3779b9u^yy*0x85ebca6bu)&255)-128;
            cache->c=(int)(random32(seed^xx*0x9e3779b9u^(yy+1)*0x85ebca6bu)&255)-128;
        }
        cache->b=(int)(random32(seed^(xx+1)*0x9e3779b9u^yy*0x85ebca6bu)&255)-128;
        cache->d=(int)(random32(seed^(xx+1)*0x9e3779b9u^(yy+1)*0x85ebca6bu)&255)-128;
        cache->x=xx;cache->y=yy;
    }
    int dx=(int)(x&(scale-1)),dy=(int)(y&(scale-1)),sx=(int)scale-dx,sy=(int)scale-dy;
    return (cache->a*sx*sy+cache->b*dx*sy+cache->c*sx*dy+cache->d*dx*dy)>>(size*2);
}
static uint32_t leak(uint32_t px,uint32_t py,const m10v_film_effects *e,uint32_t seed){
    if(!e->leak_gain)return 0;
    uint32_t position=e->leak_position;
    if(position==5)position=random32(seed^0x5207u)%5;
    uint32_t d=position==0?px:position==1?255-px:position==2?py:position==3?255-py:px+py;
    uint32_t span=24+e->leak_spread*24;
    if(d>=span)return 0;
    static const uint32_t reciprocal[9]={699050,349525,233016,174762,139810,116508,99864,87381,77672};
    uint32_t weight=((span-d)*reciprocal[e->leak_spread])>>16;weight=weight*weight>>8;
    int ripple=noise(px>>1,py>>1,seed^0xa1734u,3);
    return weight*e->leak_gain*(uint32_t)(192+ripple/4)/(8*256);
}
static uint32_t divide(uint32_t n,uint32_t d){uint32_t q=0,r=0;for(int i=31;i>=0;i--){r=(r<<1)|((n>>i)&1);if(r>=d){r-=d;q|=1u<<i;}}return q;}
static __attribute__((always_inline)) inline void texture(m10v_library_image *im,const m10v_film_effects *e,uint32_t grain,uint32_t seed,uint32_t color,uint32_t use_leak,void *memory,uint32_t use_cache,uint32_t *stats){
    if(!color&&!grain&&!e->leak_gain)return;
    uint32_t sx=divide(256u<<16,im->width),sy=divide(256u<<16,im->height);
    uint32_t grain_sx=divide(6000u<<12,im->width),grain_sy=divide(4000u<<12,im->height);
    uint32_t leak_seed=e->leak_variation?seed:0x5207250du;
    grain_lattice lattice={0xffffffffu,0xffffffffu,0,0,0,0};
    uint8_t leak_row[256];uint32_t leak_y=0xffffffffu;
#if M10V_TEXTURE_NEON
    m10v_texture_block_params block;
    block.grain_q8=grain;
    const uint8_t *table=color==1?&m10v_5207_lut[0][0]:color>=2?m10v_harman_texture_table(color-2):0;
#endif
#if M10V_SPATIAL_NEON
    uint32_t gx8[8],hash8[8],noise_ready=0;int32_t noise8[8];
#endif
    for(uint32_t y=0;y<im->height;y++){
#if M10V_SPATIAL_NEON
    noise_ready=0;
#endif
    if(use_leak){
        uint32_t py=(y*sy)>>16;
        if(py!=leak_y){
            for(uint32_t px=0;px<256;px++)leak_row[px]=(uint8_t)leak(px,py,e,leak_seed);
            leak_y=py;
        }
    }
    for(uint32_t x=0;x<im->width;x+=2){
#if M10V_SPATIAL_NEON
        if(!(x&7u)){
          noise_ready=0;
          if(grain&&x+8<=im->width){
            for(uint32_t k=0;k<8;k++)gx8[k]=((x+k)*grain_sx)>>12;
            noise_ready=m10v_spatial_grain_noise8(gx8,(y*grain_sy)>>12,seed,e->grain_size,hash8,noise8)==0;
          }
        }
#endif
        uint32_t at=y*im->stride+x;int cb=(int)im->chroma[at]-128,cr=(int)im->chroma[at+1]-128;
#if M10V_TEXTURE_NEON
        /* Cache selection must not bypass batching. Exact full RGB keys and
         * mapped colors are shared with the scalar tail before grain. */
        if(x+8<=im->width&&(!grain||noise_ready)){
            for(uint32_t k=0;k<8;k++){
                block.light[k]=use_leak?leak_row[((x+k)*sx)>>16]:0;
                block.hashes[k]=grain?hash8[k]:0;block.noise[k]=grain?noise8[k]:0;
            }
            int hits=table?m10v_texture_block8_cached(im->y+at,im->chroma+at,table,&block,use_cache?memory:0):m10v_texture_effects_block8(im->y+at,im->chroma+at,&block,e->leak_gain!=0);
            if(hits>=0){if(stats){stats[0]+=8;stats[1]+=(uint32_t)hits;}x+=6;continue;}
            if(stats)stats[2]|=8;
        }
#endif
        uint8_t mapped[2][3],original[2][3];
        for(uint32_t k=0;k<2;k++){
            int v=im->y[at+k];uint8_t rgb[3]={clip(v+roundq(91881*cr,16)),clip(v-roundq(22554*cb+46802*cr,16)),clip(v+roundq(116130*cb,16))};
            for(uint32_t c=0;c<3;c++)original[k][c]=rgb[c];
            if(use_leak){
            uint32_t light=leak_row[((x+k)*sx)>>16];
            /* Bounded warm exposure approximation in the assumed encoded input. */
            static const uint32_t transmission[3]={256,112,36};
            for(uint32_t c=0;c<3;c++)rgb[c]=clip(rgb[c]+(int)(light*transmission[c]*(255-rgb[c])>>16));
            }
            if(color){
                uint32_t key=(uint32_t)rgb[0]|((uint32_t)rgb[1]<<8)|((uint32_t)rgb[2]<<16);
                uint32_t *entry=use_cache?m10v_color_cache_slot(memory,key):0;
                if(use_cache&&entry[0]==(key|0x01000000u)){m10v_color_cache_read(entry,mapped[k]);if(stats)stats[1]++;}else{
                    if(color==1)m10v_5207_rgb(rgb,mapped[k]);else m10v_harman_rgb(color-2,rgb,mapped[k]);
                    if(use_cache)m10v_color_cache_write(entry,key,mapped[k]);
                }
            }else for(uint32_t c=0;c<3;c++)mapped[k][c]=rgb[c];
            if(grain){
                uint32_t gx=((x+k)*grain_sx)>>12,gy=(y*grain_sy)>>12;
                uint32_t h;int n;
#if M10V_SPATIAL_NEON
                if(noise_ready){h=hash8[(x+k)&7u];n=noise8[(x+k)&7u];}else
#endif
                {h=random32(seed^gx*0x9e3779b9u^gy*0x85ebca6bu);
                 n=grain_noise(gx,gy,seed,e->grain_size,h,&lattice)+((int)(h&255)-128)/3;}
                int lum=(54*mapped[k][0]+183*mapped[k][1]+19*mapped[k][2])>>8;
                int weight=32+(lum<128?lum:255-lum);
                int delta=n*(int)grain*weight/(128*24*256);
                for(uint32_t c=0;c<3;c++)mapped[k][c]=clip((int)mapped[k][c]+delta+((int)((h>>(c*8))&255)-128)*(int)grain/(192*256));
            }
            int r=mapped[k][0],g=mapped[k][1],b=mapped[k][2];
            if(!color){r-=original[k][0];g-=original[k][1];b-=original[k][2];}
            im->y[at+k]=clip((color?0:im->y[at+k])+roundq(19595*r+38470*g+7471*b,16));
        }
        int r=mapped[0][0]+mapped[1][0],g=mapped[0][1]+mapped[1][1],b=mapped[0][2]+mapped[1][2];
        if(!color){r-=original[0][0]+original[1][0];g-=original[0][1]+original[1][1];b-=original[0][2]+original[1][2];}
        if(color||e->leak_gain){im->chroma[at]=clip((color?128:im->chroma[at])+roundq(-11059*r-21709*g+32768*b,17));
        im->chroma[at+1]=clip((color?128:im->chroma[at+1])+roundq(32768*r-27439*g-5329*b,17));}
    }
    }
}

/* Resolve invariant color/leak branches once per image. Besides avoiding the
 * disabled leak pass, constant color lets ARM discard the original-RGB copy
 * and delta conversions for LUT rendering. No extra image buffer is needed. */
static __attribute__((always_inline)) inline void texture_dispatch(m10v_library_image *im,const m10v_film_effects *e,uint32_t grain,uint32_t seed,uint32_t color,void *memory,uint32_t cached,uint32_t *stats){
    if(color==0){
        if(e->leak_gain)texture(im,e,grain,seed,0,1,0,0,stats);else texture(im,e,grain,seed,0,0,0,0,stats);
    }else if(color==1){
        if(e->leak_gain)texture(im,e,grain,seed,1,1,memory,cached,stats);else texture(im,e,grain,seed,1,0,memory,cached,stats);
    }else{
        if(e->leak_gain)texture(im,e,grain,seed,color,1,memory,cached,stats);else texture(im,e,grain,seed,color,0,memory,cached,stats);
    }
}
void m10v_5207_texture_cached_stats_q8(m10v_library_image *im,const m10v_film_effects *e,uint32_t grain,uint32_t seed,uint32_t color,void *memory,uint32_t stats[3]){
    if(stats){stats[0]=0;stats[1]=0;stats[2]=(memory?4u:0u)|(M10V_TEXTURE_NEON?2u:0u);}
    if(!color&&!grain&&!e->leak_gain)return;
    memory=color?m10v_color_cache_prepare(memory,im):0;
    if(stats&&memory)stats[2]|=1;
    if(memory)texture_dispatch(im,e,grain,seed,color,memory,1,stats);
    else texture_dispatch(im,e,grain,seed,color,0,0,stats);
}
void m10v_5207_texture_cached_q8(m10v_library_image *im,const m10v_film_effects *e,uint32_t grain,uint32_t seed,uint32_t color,void *memory){m10v_5207_texture_cached_stats_q8(im,e,grain,seed,color,memory,0);}

void m10v_5207_texture_q8(m10v_library_image *im,const m10v_film_effects *e,uint32_t grain,uint32_t seed,uint32_t color){m10v_5207_texture_cached_q8(im,e,grain,seed,color,0);}

void m10v_5207_texture(m10v_library_image *im,const m10v_film_effects *e,uint32_t grain,uint32_t seed,uint32_t color){m10v_5207_texture_q8(im,e,grain<<8,seed,color);}
void m10v_5207_render(m10v_library_image *im,const m10v_film_effects *e,uint32_t grain,uint32_t seed){m10v_5207_texture(im,e,grain,seed,1);}
