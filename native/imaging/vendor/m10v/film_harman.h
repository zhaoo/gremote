#ifndef M10V_FILM_HARMAN_H
#define M10V_FILM_HARMAN_H
#include <stdint.h>
/* Own research-guided reference: index0 PhoenixII, 1 RED125, 2 RED64, 3 RED250; dispatcher14 PhoenixII EI120.
 * Not a measured film or GR3 calibration; see harman-reference.json. */
void m10v_harman_rgb(uint32_t index,const uint8_t rgb[3],uint8_t out[3]);
#if M10V_TEXTURE_NEON
const uint8_t *m10v_harman_texture_table(uint32_t index);
#endif
#endif
