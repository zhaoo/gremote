#ifndef M10V_HALATION_CORE_H
#define M10V_HALATION_CORE_H
#include <stdint.h>
/* Explicit software ABI; neither value asserts the camera's byte order. */
enum { M10V_CBCR422 = 1, M10V_CRCB422 = 2 };
enum { M10V_HALO_OK = 0, M10V_HALO_INVALID = 1, M10V_HALO_SCRATCH = 2 };
typedef struct {
    uint8_t *y, *chroma;
    uint32_t y_bytes, chroma_bytes, width, height, y_stride, chroma_stride, format;
} m10v_halo_image;
/* width 2..6144 even; height 1..4096. Scratch: 6*ceil(width/step)*ceil(height/step), where step is the smallest
 * power of two giving a grid <=384 columns and <=256 rows (max 589824 bytes).
 * Scratch size is rounded up to 4 bytes and its base must be 4-byte aligned.
 * All regions must be disjoint. Invalid inputs leave all regions untouched.
 * control: legacy 0 off, 1 weak, 2 natural; or bit31 plus five 0..8 nibbles
 * at bits0/4/8/12/16: gain/radius/threshold/grain/profile. Other bits zero.
 * Profile0 disables halo,1..2 weak,3..5 natural,6..8 strong. Grain is independent.
 * No allocation, I/O or camera API calls. */
int m10v_halation(const m10v_halo_image *image, uint32_t strength,
                  uint8_t *scratch, uint32_t scratch_bytes);
#endif
