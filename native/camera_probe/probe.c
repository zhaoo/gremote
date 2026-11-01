#include "probe.h"
static uint32_t word(const uint8_t*p){return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static int same(const uint8_t*a,const uint8_t*b,uint32_t n){for(uint32_t i=0;i<n;i++)if(a[i]!=b[i])return 0;return 1;}
int mc_probe_observe(const mc_probe_target*t,const mc_probe_io*io,mc_probe_result*out){
 if(!t||!io||!io->read||!out)return MC_PROBE_MEMORY;
 out->run_id=out->sequence=out->value=out->packet_tag=0;
 uint8_t bytes[16],count[2],descriptor[8],again[8],a[64],b[64];
 for(uint32_t i=0;i<MC_PROBE_ANCHORS;i++){
  if(!io->read(io->ctx,t->anchors[i].address,bytes,16))return MC_PROBE_MEMORY;
  if(!same(bytes,t->anchors[i].bytes,16))return MC_PROBE_IDENTITY;
 }
 if(!io->read(io->ctx,t->array_count,count,2)||!io->read(io->ctx,t->array_table,descriptor,8))return MC_PROBE_MEMORY;
 if(count[0]!=1||count[1]!=0||word(descriptor)!=MC_PROBE_WORDS)return MC_PROBE_ARRAY;
 uint32_t address=word(descriptor+4);
 if((address&3)||t->heap_end<t->heap_min||t->heap_end-t->heap_min<sizeof(a)||address<t->heap_min||address>t->heap_end-sizeof(a))return MC_PROBE_BOUNDS;
 if(!io->read(io->ctx,address,a,sizeof(a)))return MC_PROBE_MEMORY;
 if(word(a)!=MC_PROBE_MAGIC||word(a+4)!=1||word(a+8)==0||word(a+8)>0x3fffffffu||word(a+12)==0||word(a+12)>16||word(a+16)!=12345+17*word(a+12)||word(a+20)!=t->packet_tag||word(a+24)!=0)return MC_PROBE_PACKET;
 for(uint32_t i=7;i<MC_PROBE_WORDS;i++)if(word(a+i*4)!=MC_PROBE_CANARY+i)return MC_PROBE_PACKET;
 if(!io->read(io->ctx,t->array_count,count,2)||!io->read(io->ctx,t->array_table,again,8)||!io->read(io->ctx,address,b,sizeof(b)))return MC_PROBE_MEMORY;
 if(count[0]!=1||count[1]!=0||!same(descriptor,again,8)||!same(a,b,sizeof(a)))return MC_PROBE_CHANGED;
 out->run_id=word(a+8);out->sequence=word(a+12);out->value=word(a+16);out->packet_tag=word(a+20);
 return MC_PROBE_OK;
}
