#include "state_reader.h"
static uint32_t word(const uint8_t*p){return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static int equal(const uint8_t*a,const uint8_t*b,uint32_t n){for(uint32_t i=0;i<n;i++)if(a[i]!=b[i])return 0;return 1;}
static int read_bytes(const mc_probe_io*io,uint32_t at,uint8_t*out,uint32_t n){
 while(n){uint32_t count=n>64?64:n;if(at>0xffffffffu-count||!io->read(io->ctx,at,out,count))return 0;at+=count;out+=count;n-=count;}return 1;
}
static uint32_t crc(const uint8_t*p,uint32_t n){uint32_t c=0xffffffffu;for(uint32_t i=0;i<n;i++){c^=p[i];for(unsigned j=0;j<8;j++)c=(c>>1)^(0xedb88320u&(0u-(c&1u)));}return ~c;}
int mc_state_observe(const mc_state_target*t,const mc_probe_io*io,mc_state_result*out){
 if(!out)return MC_STATE_MEMORY;
 out->owner=out->version=0;for(uint32_t i=0;i<MC_STATE_BYTES;i++)out->state[i]=0;
 if(!t||!io||!io->read)return MC_STATE_MEMORY;
 uint8_t guard[4],pointer[4],head[8],again[8],first[MC_STATE_BYTES],second[MC_STATE_BYTES];
 if(!read_bytes(io,t->guard,guard,4)||!read_bytes(io,t->owner_pointer,pointer,4))return MC_STATE_MEMORY;
 if(!(word(guard)&1u))return MC_STATE_UNAVAILABLE;
 uint32_t owner=word(pointer);
 if((owner&3u)||t->cache_bytes<8+MC_STATE_BYTES||t->cache_offset>0xffffffffu-t->cache_bytes||t->heap_end<t->heap_min||t->cache_offset+t->cache_bytes>t->heap_end-t->heap_min||owner<t->heap_min||owner>t->heap_end-t->cache_offset-t->cache_bytes)return MC_STATE_UNAVAILABLE;
 uint32_t cache=owner+t->cache_offset;
 if(!read_bytes(io,cache,head,8))return MC_STATE_MEMORY;
 if(word(head)!=0x3856504du||!word(head+4))return MC_STATE_UNAVAILABLE;
 if(word(head+4)&1u)return MC_STATE_BUSY;
 if(!read_bytes(io,cache+8,first,sizeof(first)))return MC_STATE_MEMORY;
 if(word(first)!=0x5630314du||first[4]!=5||first[5]||first[6]!=MC_STATE_BYTES||first[7]||word(first+180)!=crc(first,180)||(word(first+176)&~1u))return MC_STATE_INVALID;
 if(!read_bytes(io,cache+8,second,sizeof(second))||!read_bytes(io,cache,again,8)||!read_bytes(io,t->owner_pointer,pointer,4)||!read_bytes(io,t->guard,guard,4))return MC_STATE_MEMORY;
 if(!(word(guard)&1u)||word(pointer)!=owner||!equal(head,again,8)||!equal(first,second,sizeof(first)))return MC_STATE_CHANGED;
 out->owner=owner;out->version=word(head+4);for(uint32_t i=0;i<sizeof(first);i++)out->state[i]=first[i];
 return MC_STATE_OK;
}
