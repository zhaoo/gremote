#include <stdint.h>
#include "film_newstocks_data.h"
/* 60,750-byte immutable table bank, independently linked below 64 KiB. */
const uint8_t *m10v_newstocks_table(uint32_t variant){return variant<6?&m10v_newstocks_luts[variant][0][0]:0;}
