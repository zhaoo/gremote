#ifndef M10V_CAPTURE_PROFILE_H
#define M10V_CAPTURE_PROFILE_H
#include <stdint.h>
#ifndef M10V_CAPTURE_PROFILE
#define M10V_CAPTURE_PROFILE 0
#endif
#if M10V_CAPTURE_PROFILE
/* Stack-owned trace, never retained by the renderer or shared across shots.
 * Original 0x536afc5c calls this same OS service with an 8-byte output: it
 * converts {signed high, low} to uint64. Call the scalar SVC facade directly
 * so no extra VFP/NEON state is introduced. 0 is success. The SVC table
 * routes 0x80510100 to 0x53067c24, the T-Kernel operating-time getter (ms);
 * it reads the same 64-bit counter advanced by TTimPeriod. Failures never
 * abort a JPEG. */
typedef struct {uint32_t count,context;uint32_t events[32][5];} m10v_capture_profile;
static inline void m10v_profile_mark(m10v_capture_profile *p,uint32_t stage){
    if(!p||p->count>=32)return;
    uint32_t time[2]={0,0};
    int status=((int (*)(uint32_t *))0x53050b7cu)(time);
    uint32_t *e=p->events[p->count++];
    e[0]=150;e[1]=p->context;e[2]=stage|(status?0x80000000u:0);
    e[3]=time[1];e[4]=time[0];
}
#define M10V_PROFILE(stage) m10v_profile_mark(profile,stage)
#else
#define M10V_PROFILE(stage) ((void)0)
#endif
#endif
