#ifndef M10V_COLOR_CACHE_H
#define M10V_COLOR_CACHE_H
#include <stdint.h>
/* Optional, caller-owned, reset per capture. Full 24-bit key comparison makes
 * every hit exact; collisions recompute. Never quantize or retain image state. */
#define M10V_COLOR_CACHE_BYTES 65536u
static inline uint32_t *m10v_color_cache_slot(void *memory,uint32_t key){
    return (uint32_t *)memory+((key*0x9e3779b9u)>>19)*2;
}
static inline void m10v_color_cache_read(const uint32_t *slot,uint8_t rgb[3]){
    uint32_t value=slot[1];rgb[0]=(uint8_t)value;rgb[1]=(uint8_t)(value>>8);rgb[2]=(uint8_t)(value>>16);
}
static inline void m10v_color_cache_write(uint32_t *slot,uint32_t key,const uint8_t rgb[3]){
    slot[0]=key|0x01000000u;slot[1]=(uint32_t)rgb[0]|((uint32_t)rgb[1]<<8)|((uint32_t)rgb[2]<<16);
}
static inline void *m10v_color_cache_prepare(void *memory,const m10v_library_image *im){
    if(!memory)return 0;
    uint32_t *entries=(uint32_t *)memory;
    for(uint32_t i=0;i<M10V_COLOR_CACHE_BYTES/4;i+=2)entries[i]=0;
    /* Bounded 1024-pixel input probe. Select the uncached specialized loop
     * for high-entropy scenes; do not pay cache checks on every noisy pixel.
     * This probe is only a performance heuristic, never an image transform. */
    uint32_t rows=im->height<16?im->height:16;
    uint32_t cols=im->width<64?im->width/2:32;
    uint32_t dy=im->height<16?1:im->height>>4;
    uint32_t dx=im->width<64?2:(im->width>>5)&~1u;
    uint32_t hits=0;
    for(uint32_t row=0;row<rows;row++)for(uint32_t col=0;col<cols;col++){
        uint32_t at=row*dy*im->stride+col*dx;
        uint32_t uv=((uint32_t)im->chroma[at]<<8)|((uint32_t)im->chroma[at+1]<<16);
        for(uint32_t k=0;k<2;k++){
            uint32_t key=uv|im->y[at+k],*slot=m10v_color_cache_slot(memory,key);
            if(slot[0]==(key|0x01000000u))++hits;
            slot[0]=key|0x01000000u;
        }
    }
    for(uint32_t i=0;i<M10V_COLOR_CACHE_BYTES/4;i+=2)entries[i]=0;
    return hits*4>=rows*cols*2?memory:0;
}
#endif
