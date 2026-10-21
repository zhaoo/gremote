#include "film_harman.h"
#include "film_harman_data.h"
extern const uint8_t *m10v_curated_table(uint32_t);
extern const uint8_t *m10v_newstocks_table(uint32_t);
#if M10V_FILM_COLOR_CANDIDATE
#include "m10v_film_color_candidates.h"
#endif
static uint8_t clip(int x){return (uint8_t)(x<0?0:x>255?255:x);}
#if M10V_TEXTURE_NEON
const uint8_t *m10v_harman_texture_table(uint32_t variant){
    if(variant==14)return &m10v_harman_luts[4][0][0];
    if(variant>13)return 0;
#if M10V_FILM_COLOR_CANDIDATE
    if(variant==0)return &m10v_phoenix_ii_candidate_lut[0][0];
#endif
    return variant>=8?m10v_newstocks_table(variant-8):variant>=4?m10v_curated_table(variant-4):&m10v_harman_luts[variant][0][0];
}
#endif
void m10v_harman_rgb(uint32_t variant,const uint8_t rgb[3],uint8_t out[3]){
    if(variant>14){for(uint32_t c=0;c<3;c++)out[c]=rgb[c];return;}
    const uint8_t (*table)[3]=variant==14?m10v_harman_luts[4]:variant>=8?(const uint8_t (*)[3])m10v_newstocks_table(variant-8):variant>=4?(const uint8_t (*)[3])m10v_curated_table(variant-4):m10v_harman_luts[variant];
#if M10V_FILM_COLOR_CANDIDATE
    if(variant==0)table=m10v_phoenix_ii_candidate_lut;
#endif
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
    const uint8_t *a=table[index],*b=table[index+s0],*c=table[index+s0+s1],*d=table[index+(225+15+1)];
    uint32_t w0=255-f0,w1=f0-f1,w2=f1-f2;
    out[0]=clip((int)((w0*a[0]+w1*b[0]+w2*c[0]+f2*d[0]+127)/255));
    out[1]=clip((int)((w0*a[1]+w1*b[1]+w2*c[1]+f2*d[1]+127)/255));
    out[2]=clip((int)((w0*a[2]+w1*b[2]+w2*c[2]+f2*d[2]+127)/255));
}
