#include <stdint.h>
#include "film_curated_data.h"
/* Separate immutable table bank keeps each linked module below 64 KiB. */
const uint8_t *m10v_curated_table(uint32_t variant){
    return variant<4?&m10v_curated_luts[variant][0][0]:0;
}
