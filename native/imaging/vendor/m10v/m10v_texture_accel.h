#ifndef M10V_TEXTURE_ACCEL_H
#define M10V_TEXTURE_ACCEL_H
#include <stdint.h>
/* Exactly eight full-color YUV422 pixels. LUT is3375 interleaved RGB triples.
 * Caller supplies precomputed leak and EXACT noise8 including fine-noise /3.
 * grain_q8<=1024; noise[-170,169]. Disjoint buffers, LUT and params required.
 * ARM caller establishes task NEON ownership. No ISP operation or allocation.
 * Invalid scalar params return-1 before writes. LUT/planes must be valid RAM. */
typedef struct {
 uint8_t light[8];
 uint32_t grain_q8;
 uint32_t hashes[8];
 int32_t noise[8];
} m10v_texture_block_params;
int m10v_texture_block8(uint8_t *y,uint8_t *uv,const uint8_t *lut,const m10v_texture_block_params *p);
/* Optional caller-owned 64KiB cache, aligned4, reset when capture or LUT changes.
 * Full RGB24 keys are compared AFTER leak and cache stores PRE-grain LUT RGB.
 * No shared state. Returns observed hits0..8 or-1. Null cache is uncached SIMD.
 * All-four-lane hits skip interpolation; partial hits recompute the four lanes.
 * Cache/planes/params/LUT must be disjoint with lifetimes spanning the call. */
int m10v_texture_block8_cached(uint8_t *y,uint8_t *uv,const uint8_t *lut,const m10v_texture_block_params *p,void *cache);
/* Exact no-LUT residual effects: delta RGB is added to the original YUV.
 * chroma_enabled must be0/1, and caller sets it only for active leak gain.
 * No LUT or cache reads; grain-only retains original UV bytes. */
int m10v_texture_effects_block8(uint8_t *y,uint8_t *uv,const m10v_texture_block_params *p,uint32_t chroma_enabled);
#endif
