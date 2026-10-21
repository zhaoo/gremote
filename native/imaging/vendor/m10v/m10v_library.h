#ifndef M10V_LIBRARY_H
#define M10V_LIBRARY_H
#include <stdint.h>

#define M10V_FILM_COUNT 78u
#define M10V_CUSTOM_MAX_ID 288u
/* 79..288 are existing custom identities. Never reuse them. */
#define M10V_CHAR_ID 289u
#define M10V_BUILTIN(id) ((id)>0 && ((id)<=M10V_FILM_COUNT || (id)==M10V_CHAR_ID))
#define M10V_CUSTOM(id) ((id)>M10V_FILM_COUNT && (id)<=M10V_CUSTOM_MAX_ID)
#define M10V_SLOT_COUNT 5u
#define M10V_LIBRARY_OK 0
#define M10V_LIBRARY_INVALID -1
#define M10V_LIBRARY_STORE_FAILED -2

typedef struct { uint16_t film; uint8_t grain, soft, halo_gain, halo_spread, halo_threshold, halo_profile; } m10v_slot;
typedef struct { uint8_t grain_size, leak_gain, leak_position, leak_spread, leak_variation, film_exposure, reserved[2]; } m10v_film_effects;
typedef struct {
    uint32_t magic;
    uint16_t version, size;
    uint32_t sequence;
    m10v_slot slots[M10V_SLOT_COUNT];
    uint8_t stamp, format, corner, color;
    m10v_film_effects effects[M10V_SLOT_COUNT];
    uint32_t reserved, crc;
} m10v_library_state;
typedef struct {
    uint8_t *y, *chroma;
    uint32_t y_bytes, chroma_bytes, width, height, stride;
} m10v_library_image;
typedef struct { uint16_t year; uint8_t month, day, hour, minute; } m10v_library_date;
typedef int (*m10v_library_store)(void *, const m10v_library_state *);

int m10v_library_effects(m10v_library_state *,uint32_t slot,uint32_t field,uint32_t value,m10v_library_store,void *);
int m10v_camera_library_effects(m10v_library_state *,uint32_t slot,uint32_t field,uint32_t value);
int m10v_library_reset(m10v_library_state *,uint32_t slot,m10v_library_store,void *);
int m10v_camera_library_reset(m10v_library_state *,uint32_t slot);
void m10v_library_init(m10v_library_state *);
int m10v_library_valid(const m10v_library_state *);
const char *m10v_library_name(uint32_t film);
int m10v_library_select(m10v_library_state *, uint32_t slot, uint32_t film,
                        m10v_library_store, void *);
int m10v_library_select_custom(m10v_library_state *,uint32_t slot,uint32_t film,uint32_t bank,m10v_library_store,void *);
int m10v_library_texture(m10v_library_state *, uint32_t slot, uint32_t grain, uint32_t soft,
                         m10v_library_store, void *);
int m10v_library_halation(m10v_library_state *, uint32_t slot, uint32_t gain, uint32_t spread, uint32_t threshold, uint32_t profile, m10v_library_store, void *);
int m10v_library_detail(m10v_library_state *, uint32_t slot, uint32_t gain, uint32_t spread, uint32_t threshold, uint32_t grain, uint32_t soft, m10v_library_store, void *);
int m10v_library_tables(uint32_t film, int16_t *, int16_t *, uint16_t *, uint16_t *);
int m10v_library_stamp(m10v_library_state *, uint32_t enabled, uint32_t format,
                       uint32_t corner, uint32_t color, m10v_library_store, void *);
int m10v_library_film_name_stamp(m10v_library_state *,uint32_t enabled,m10v_library_store,void *);
/* Upstream completion is per recipe; callers must validate generation and
 * frame identity before supplying this mask. These bits never disable an
 * effect that the native owner has not actually executed. */
enum { M10V_NATIVE_COLOR=1u, M10V_NATIVE_GRAIN=2u, M10V_NATIVE_SOFT=4u,
       M10V_NATIVE_HALO=8u, M10V_NATIVE_LEAK=16u, M10V_NATIVE_ALL=31u };
/* CPU residual plan after the recipe owner has authenticated completion.
 * No pixel access and no state mutation. A disabled halo has no spatial pass;
 * uncompleted native work always retains its software fallback. */
#define M10V_CPU_STAMP 32u
static inline uint32_t m10v_library_cpu_stages(const m10v_library_state *state,uint32_t slot,uint32_t completed){
    const m10v_slot *v=&state->slots[slot];
    uint32_t stages=(v->film>M10V_FILM_COUNT||!(completed&M10V_NATIVE_COLOR))?M10V_NATIVE_COLOR:0;
    if(v->grain&&!(completed&M10V_NATIVE_GRAIN))stages|=M10V_NATIVE_GRAIN;
    if((v->film==33||v->film==67)&&v->halo_gain&&!(completed&M10V_NATIVE_HALO))stages|=M10V_NATIVE_HALO;
    if(state->effects[slot].leak_gain&&!(completed&M10V_NATIVE_LEAK))stages|=M10V_NATIVE_LEAK;
    if(state->stamp||(state->reserved&1u))stages|=M10V_CPU_STAMP;
    return stages;
}
int m10v_library_render_native(m10v_library_image *,const m10v_library_state *,uint32_t,
        const m10v_library_date *,uint32_t,uint8_t *,uint32_t,uint32_t completed);
int m10v_library_render_custom(m10v_library_image *,const m10v_library_state *,uint32_t,
        const m10v_library_date *,uint32_t,uint8_t *,uint32_t,uint32_t completed,const uint8_t *lut,const char *name);
int m10v_library_render(m10v_library_image *, const m10v_library_state *, uint32_t slot,
                        const m10v_library_date *, uint32_t seed, uint8_t *scratch,
                        uint32_t scratch_bytes);
/* Nonnegative load provenance: 0=new journal, 1=defaults, 2=v2 migration,
 * 3=v1 migration. All are usable validated states; negative is failure. */
int m10v_camera_library_preview(m10v_library_state *);
void m10v_camera_library_preview_init(uint32_t);
void m10v_camera_library_preview_clear(uint32_t);
int m10v_camera_library_load(m10v_library_state *);
int m10v_camera_library_select(m10v_library_state *, uint32_t slot, uint32_t film);
int m10v_camera_library_select_custom(m10v_library_state *,uint32_t slot,uint32_t film,uint32_t bank);
int m10v_camera_library_texture(m10v_library_state *, uint32_t slot, uint32_t grain, uint32_t soft);
int m10v_camera_library_halation(m10v_library_state *, uint32_t slot, uint32_t gain, uint32_t spread, uint32_t threshold, uint32_t profile);
int m10v_camera_library_detail(m10v_library_state *, uint32_t slot, uint32_t gain, uint32_t spread, uint32_t threshold, uint32_t grain, uint32_t soft);
int m10v_camera_library_stamp(m10v_library_state *, uint32_t enabled, uint32_t format,
                             uint32_t corner, uint32_t color);
int m10v_camera_library_film_name_stamp(m10v_library_state *,uint32_t enabled);
#endif
