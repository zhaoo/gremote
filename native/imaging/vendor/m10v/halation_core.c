#include "halation_core.h"
/* Single text function, no tables or external calls, so the ARM object needs
 * no linker/runtime helpers. Integer arithmetic is identical on host and ARM. */
#define INLINE static inline __attribute__((always_inline))
INLINE uint32_t overlap(uintptr_t a, uint32_t na, uintptr_t b, uint32_t nb) {
    return a < b + nb && b < a + na;
}
INLINE uint32_t valid_range(uintptr_t a, uint32_t n) { return a && n && a <= UINTPTR_MAX - n; }
INLINE uint32_t edge(uint32_t at, uint32_t count, int delta) {
    if (delta < 0 && at < (uint32_t)(-delta)) return 0;
    uint32_t v = delta < 0 ? at - (uint32_t)(-delta) : at + (uint32_t)delta;
    return v < count ? v : count - 1;
}
INLINE uint8_t add_sat(uint8_t a, uint32_t b) { uint32_t n = a + b; return (uint8_t)(n > 255 ? 255 : n); }

int m10v_halation(const m10v_halo_image *image, uint32_t control,
                  uint8_t *scratch, uint32_t scratch_bytes) {
    if (!image) return M10V_HALO_INVALID;
    uint32_t strength=control,passes=control==1?2:3,threshold=control==1?210:235;
    uint32_t gain=control==1?48:80,grain=0;
    if(control&0x80000000u) {
        uint32_t g=control&15,r=(control>>4)&15,t=(control>>8)&15;
        grain=(control>>12)&15;uint32_t profile=(control>>16)&15;
        if((control&0x7ff00000u)||g>8||r>8||t>8||grain>8||profile>8)
            return M10V_HALO_INVALID;
        strength=profile?2:0;passes=1+(r>>1);threshold=223+3*t;gain=g*20;
        if(profile<=2)gain>>=1;else if(profile>=6)gain+=gain>>1;
    } else if(control>2)return M10V_HALO_INVALID;
    /* Copy inputs before any writes; avoid caller-owned header changing mid-call. */
    uint8_t *y = image->y, *c = image->chroma;
    uint32_t w = image->width, h = image->height, ys = image->y_stride,
             cs = image->chroma_stride, fmt = image->format;
    if (w < 2 || w > 6144 || (w & 1) || !h || h > 4096 ||
        ys < w || ys > 16384 || cs < w || cs > 16384 || (cs & 1) ||
        (fmt != M10V_CBCR422 && fmt != M10V_CRCB422)) return M10V_HALO_INVALID;
    /* Limits above make these products safe in uint32. */
    uint32_t yn = (h - 1) * ys + w, cn = (h - 1) * cs + w;
    uintptr_t ya = (uintptr_t)y, ca = (uintptr_t)c;
    if (image->y_bytes < yn || image->chroma_bytes < cn ||
        !valid_range(ya, image->y_bytes) || !valid_range(ca, image->chroma_bytes) ||
        overlap(ya, image->y_bytes, ca, image->chroma_bytes)) return M10V_HALO_INVALID;
    if ((!strength||!gain)&&!grain) return M10V_HALO_OK;
    /* Keep a bounded normalized grid. Power-of-two cells scale the radius
     * with output dimensions without integer division or unbounded allocation. */
    uint32_t shift = 0, step = 1;
    while (((w+step-1)>>shift) > 384 || ((h+step-1)>>shift) > 256) { ++shift; step <<= 1; }
    uint32_t gw = (w+step-1)>>shift, gh = (h+step-1)>>shift, cells = gw * gh, need = (6 * cells+3)&~3u;
    uintptr_t sa = (uintptr_t)scratch;
    if (scratch_bytes < need || !scratch) return M10V_HALO_SCRATCH;
    if ((sa&3) || !valid_range(sa, scratch_bytes) || overlap(sa, scratch_bytes, ya, image->y_bytes) ||
        overlap(sa, scratch_bytes, ca, image->chroma_bytes)) return M10V_HALO_INVALID;
    if(!strength||!gain)goto apply_grain;
    uint8_t *a = scratch, *b = scratch + cells, *d = scratch + 2 * cells;
    for (uint32_t i = 0; i < cells; ++i) a[i] = 0;
    /* Max pooling preserves sub-grid point sources. Source mask is complete
     * before output writes and cannot feed back into its own expansion. */
    for (uint32_t row = 0; row < h; ++row) {
        for (uint32_t x = 0; x < w; ++x) {
            uint32_t light = y[row * ys + x];
            uint32_t v=light>threshold?(light-threshold)*(strength==1?4:12):0;
            /* Green-tinted specular foliage is not a neutral/warm emitter. */
            if(c[row*cs+(x&~1u)+(fmt==M10V_CBCR422?1:0)]<112)v=0;
            if(v>255)v=255;
            uint32_t at = (row >> shift) * gw + (x >> shift);
            if (v > a[at]) a[at] = (uint8_t)v;
        }
    }
    /* Current camera controls use compact two-dimensional emitters. A cable
     * or road stripe stays bright on opposite sides of a local square; a lamp
     * falls away in both axes. Scan full sides so slanted thin lines cannot
     * slip between a few directional samples. Read a completely, write b,
     * then copy: source classification never feeds back into itself. Legacy
     * controls retain their established rendering for older adapter callers. */
    if(control&0x80000000u) {
        for(uint32_t row=0;row<gh;++row)for(uint32_t x=0;x<gw;++x) {
            uint32_t center=a[row*gw+x],best=0;
            /* A seed needs a hot core at least eight luminance levels above
             * the selected threshold. Dim, point-like reflections alone are
             * insufficient; lower threshold still admits softer emitters. */
            if(center>=96)for(uint32_t radius=1;radius<=4;radius<<=1) {
                uint32_t surround=0,present=0,narrow=255;
                for(uint32_t axis=0;axis<2;++axis) {
                    uint32_t along=axis?row:x,count=axis?gh:gw;
                    uint32_t across=axis?x:row,span=axis?gw:gh;
                    uint32_t lo=0,hi=0,minus=edge(along,count,-(int)radius),plus=edge(along,count,(int)radius);
                    for(int k=-(int)radius;k<=(int)radius;++k) {
                        uint32_t cross=edge(across,span,k);
                        uint32_t at=axis?minus*gw+cross:cross*gw+minus;
                        uint32_t v=a[at];if(v>lo)lo=v;
                        at=axis?plus*gw+cross:cross*gw+plus;
                        v=a[at];if(v>hi)hi=v;
                    }
                    /* Every available side must fall below the core. An
                     * average accepts wire endpoints and white-wall corners.
                     * Missing sides at image borders are not source evidence. */
                    if(along<radius)lo=0;
                    if(along+radius>=count)hi=0;
                    uint32_t side=lo>hi?lo:hi;
                    if(along>=radius||along+radius<count)present|=1u<<axis;
                    if(side>surround)surround=side;
                    if(side<narrow)narrow=side;
                }
                /* Near-saturated strips may continue along one axis, but must
                 * fall away across their width at the two smallest scales. */
                if(radius<=2&&center>=192)surround=narrow;
                uint32_t contrast=present==3&&center>surround?center-surround:0;
                if(contrast>best)best=contrast;
            }
            b[row*gw+x]=best>=8&&best>=(center>>2)?(uint8_t)best:0;
        }
        for(uint32_t i=0;i<cells;++i)a[i]=b[i];
    }
    /* Reject connected broad highlights (sky, white walls), rather than
     * coloring the dark edge beside every bright region. Queue coordinates
     * fit in 16+16 bits; no integer division or recursion is required. */
    for(uint32_t i=0;i<cells;i++)b[i]=0;
    uint32_t *queue=(uint32_t *)(scratch+((2*cells+3)&~3u));
    for(uint32_t row=0;row<gh;row++)for(uint32_t x=0;x<gw;x++) {
        uint32_t first=row*gw+x;
        if(!a[first]||b[first])continue;
        uint32_t head=0,tail=1,border=0;queue[0]=(row<<16)|x;b[first]=1;
        while(head<tail) {
            uint32_t point=queue[head++],xx=point&65535,yy=point>>16;
            border|=!xx||!yy||xx+1==gw||yy+1==gh;
            for(uint32_t direction=0;direction<4;direction++) {
                uint32_t nx=xx,ny=yy;
                if(direction==0){if(!xx)continue;--nx;}
                else if(direction==1){if(xx+1==gw)continue;++nx;}
                else if(direction==2){if(!yy)continue;--ny;}
                else {if(yy+1==gh)continue;++ny;}
                uint32_t at=ny*gw+nx;
                if(a[at]&&!b[at]){b[at]=1;queue[tail++]=(ny<<16)|nx;}
            }
        }
        if(tail>(cells>>3)||(border&&tail>16))
            for(uint32_t i=0;i<tail;i++)a[(queue[i]>>16)*gw+(queue[i]&65535)]=0;
    }
    /* Fixed [1,4,6,4,1]/16 separable blur. Replicated borders have a constant
     * divisor, no division helpers, and a strict maximum of five passes. */
    for (uint32_t pass = 0; pass < passes; ++pass) {
        for (uint32_t row = 0; row < gh; ++row) {
            for (uint32_t x = 0; x < gw; ++x) {
                uint32_t base = row * gw;
                uint32_t sum = a[base + edge(x,gw,-2)] + 4*a[base + edge(x,gw,-1)] +
                               6*a[base+x] + 4*a[base + edge(x,gw,1)] + a[base + edge(x,gw,2)];
                b[base+x] = (uint8_t)((sum+8)>>4);
            }
        }
        for (uint32_t row = 0; row < gh; ++row) {
            for (uint32_t x = 0; x < gw; ++x) {
                uint32_t sum = b[edge(row,gh,-2)*gw+x] + 4*b[edge(row,gh,-1)*gw+x] +
                               6*b[row*gw+x] + 4*b[edge(row,gh,1)*gw+x] + b[edge(row,gh,2)*gw+x];
                d[row*gw+x] = (uint8_t)((sum+8)>>4);
            }
        }
        uint8_t *old = a; a = d; d = old;
    }
    /* sqrt(v*255) expands low-amplitude halos, once per grid cell; 8 steps. */
    for (uint32_t i = 0; i < cells; ++i) {
        uint32_t v = (uint32_t)a[i] * 255, root = 0;
        for (uint32_t bit = 128; bit; bit >>= 1) {
            uint32_t t = root | bit; if (t*t <= v) root = t;
        }
        /* Retain a visible fringe close to accepted emitters. Taper only
         * low-amplitude outer tails, rather than dimming the whole lamp halo.
         * The weight rises smoothly to one; all values remain <=255. */
        a[i] = (uint8_t)((control&0x80000000u)?(root*(a[i]<8?a[i]:8)+4)>>3:root);
    }
    uint32_t cb = fmt == M10V_CBCR422 ? 0 : 1, cr = cb ^ 1;
    for (uint32_t row = 0; row < h; ++row) {
        for (uint32_t x = 0; x < w; x += 2) {
            uint32_t yi = row*ys+x, ci = row*cs+x;
            uint32_t y0 = y[yi], y1 = y[yi+1];
            /* A pair shares chroma; never tint a protected highlight center. */
            if (y0 >= (strength == 1 ? threshold : 248) ||
                y1 >= (strength == 1 ? threshold : 248)) continue;
            /* Bilinear reconstruction around grid-cell centers avoids coarse
             * steps. Pair coordinates share a single chroma sample. */
            uint32_t half = step>>1, px = x + (shift ? 1 : 0),
                     gx = px < half ? 0 : (px-half)>>shift,
                     gy = row < half ? 0 : (row-half)>>shift,
                     fx = px < half ? 0 : (px-half)&(step-1),
                     fy = row < half ? 0 : (row-half)&(step-1);
            uint32_t nx = gx+1 < gw ? gx+1 : gx, ny = gy+1 < gh ? gy+1 : gy;
            uint32_t top = a[gy*gw+gx]*(step-fx) + a[gy*gw+nx]*fx;
            uint32_t bottom = a[ny*gw+gx]*(step-fx) + a[ny*gw+nx]*fx;
            uint32_t rounding = shift ? 1u<<(2*shift-1) : 0;
            uint32_t mask = (top*(step-fy) + bottom*fy + rounding)>>(2*shift);
            uint32_t protect = 255 - ((y0+y1)>>1);
            /* Bright shoulders need enough exposure to overcome the cool
             * background. Saturate the gain so dark point-source rims do not
             * receive the same threefold increase. */
            uint32_t shoulder = (248 - ((y0+y1)>>1)) * 4;
            uint32_t halo = strength == 1 ? (mask*protect*protect)>>16 :
                (mask*(shoulder < 255 ? shoulder : 255))>>8;
            uint32_t red = strength?(halo*gain)>>8:0;
            if(c[ci+cr]<112)red>>=2;
            uint32_t blue = red>>2, lift = red>>1;
            c[ci+cb] = (uint8_t)(c[ci+cb] > blue ? c[ci+cb]-blue : 0);
            c[ci+cr] = add_sat(c[ci+cr],red);
            y[yi] = add_sat((uint8_t)y0,lift); y[yi+1] = add_sat((uint8_t)y1,lift);
        }
    }
    /* Fine zero-mean luminance grain. No chroma noise, no padding writes,
     * and no noise at pure black/white. Scene values vary the deterministic
     * seed without global mutable state or camera random-number calls. */
apply_grain:;
    uint32_t random=0x9e3779b9u^(w<<16)^h;
    if(grain)for(uint32_t row=0;row<h;row++)for(uint32_t x=0;x<w;x++) {
        uint32_t at=row*ys+x,light=y[at];
        random+=light+17;random^=random<<13;random^=random>>17;random^=random<<5;
        uint32_t envelope=light<128?light:255-light;
        int32_t noise=((int32_t)(random&15)-(int32_t)((random>>4)&15))*(int32_t)(grain*envelope);
        int32_t delta=noise>=0?(noise+1024)>>11:-((-noise+1024)>>11);
        y[at]=(uint8_t)((int32_t)light+delta);
    }
    return M10V_HALO_OK;
}
