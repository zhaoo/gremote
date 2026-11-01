#ifndef MC_CAMERA_PROBE_H
#define MC_CAMERA_PROBE_H
#include <stdint.h>
#define MC_PROBE_WORDS 16u
#define MC_PROBE_ANCHORS 3u
#define MC_PROBE_MAGIC 0x4d435031u
#define MC_PROBE_CANARY 0x11ae00u
/* No memory-write callback exists. Observation never grants a lease. */
typedef struct { uint32_t address; uint8_t bytes[16]; } mc_probe_anchor;
typedef struct {
 uint32_t array_count,array_table,heap_min,heap_end,packet_tag;
 mc_probe_anchor anchors[MC_PROBE_ANCHORS];
} mc_probe_target;
typedef struct { void *ctx; int (*read)(void*,uint32_t,void*,uint32_t); } mc_probe_io;
typedef struct { uint32_t run_id,sequence,value,packet_tag; } mc_probe_result;
enum { MC_PROBE_OK,MC_PROBE_IDENTITY,MC_PROBE_ARRAY,MC_PROBE_BOUNDS,
 MC_PROBE_PACKET,MC_PROBE_CHANGED,MC_PROBE_MEMORY };
int mc_probe_observe(const mc_probe_target*,const mc_probe_io*,mc_probe_result*);
#endif
