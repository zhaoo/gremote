#ifndef MC_STATE_READER_H
#define MC_STATE_READER_H
#include "probe.h"
#define MC_STATE_BYTES 184u
/* Target constants must be bound to the inspected firmware by the caller.
 * This reads storage framing, not semantic parameter validation or a lease.
 * Two stable observations do not alone prove fresh cache or full identity. */
typedef struct {uint32_t guard,owner_pointer,heap_min,heap_end,cache_offset,cache_bytes;} mc_state_target;
typedef struct {uint32_t owner,version;uint8_t state[MC_STATE_BYTES];} mc_state_result;
enum {MC_STATE_OK,MC_STATE_MEMORY,MC_STATE_UNAVAILABLE,MC_STATE_BUSY,MC_STATE_INVALID,MC_STATE_CHANGED};
int mc_state_observe(const mc_state_target*,const mc_probe_io*,mc_state_result*);
#endif
