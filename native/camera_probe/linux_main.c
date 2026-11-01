/* Linux ARM EABI. All camera memory is opened and mapped READ ONLY. */
#include "probe.h"
#include "target_generated.h"
static uint32_t sc(uint32_t nr,uint32_t a,uint32_t b,uint32_t c,uint32_t d,uint32_t e,uint32_t f){
 register uint32_t r0 __asm__("r0")=a,r1 __asm__("r1")=b,r2 __asm__("r2")=c,r3 __asm__("r3")=d,r4 __asm__("r4")=e,r5 __asm__("r5")=f,r7 __asm__("r7")=nr;
 __asm__ volatile("svc 0":"+r"(r0):"r"(r1),"r"(r2),"r"(r3),"r"(r4),"r"(r5),"r"(r7):"memory","cc");return r0;
}
static int failed(uint32_t r){return r>=0xfffff001u;}
static int read_camera(void*ctx,uint32_t address,void*out,uint32_t length){
 if(!length||length>64||address<0x53000000u||address>0x60000000u-length)return 0;
 uint32_t physical=address&~4095u,offset=address&4095u,bytes=(offset+length+4095u)&~4095u;
 uint32_t mapping=sc(192,0,bytes,1,1,*(uint32_t*)ctx,physical>>12); /* PROT_READ, MAP_SHARED */
 if(failed(mapping)||!mapping)return 0;
 uint32_t start=mapping+offset;int ok=!sc(0xf0002,start,start+length,0,0,0,0);
 if(ok){volatile const uint8_t*p=(volatile const uint8_t*)(uintptr_t)start;for(uint32_t i=0;i<length;i++)((uint8_t*)out)[i]=p[i];}
 if(sc(91,mapping,bytes,0,0,0,0))ok=0;
 return ok;
}
static uint32_t add(char*out,uint32_t at,const char*s){while(*s)out[at++]=*s++;return at;}
static uint32_t digits(char*out,uint32_t at,uint32_t value){
 char reverse[10];uint32_t n=0;
 do{uint32_t q=(uint32_t)(((uint64_t)value*0xcccccccdull)>>35);reverse[n++]=(char)('0'+value-q*10);value=q;}while(value);
 while(n)out[at++]=reverse[--n];return at;
}
static uint32_t number(char*out,uint32_t at,uint32_t value){at=digits(out,at,value);out[at++]='\n';return at;}
static uint64_t now_ms(void){
 int32_t t[2];if(sc(263,1,(uint32_t)(uintptr_t)t,0,0,0,0)||t[0]<0||t[1]<0||t[1]>=1000000000)return 0;
 return (uint64_t)(uint32_t)t[0]*1000+(uint32_t)t[1]/1000000;
}
static uint32_t window_ms=8000;
static int current(uint64_t start){uint64_t now=now_ms();return now>=start&&now-start<window_ms;}
static int discover_wifi(uint32_t fd,char*name){
 uint8_t entries[512],query[32];uint32_t conf[2]={sizeof(entries),(uint32_t)(uintptr_t)entries};
 if(sc(54,fd,0x8912,(uint32_t)(uintptr_t)conf,0,0,0)||conf[0]>sizeof(entries)||conf[0]%32)return 0;
 unsigned found=0;
 for(uint32_t at=0;at<conf[0];at+=32){
  const uint8_t*p=entries+at;
  if(p[16]!=2||p[17]||p[20]!=192||p[21]!=168||p[22]!=0||p[23]!=1)continue;
  uint32_t length=0;while(length<16&&p[length])length++;if(!length||length==16)continue;
  for(uint32_t i=0;i<32;i++)query[i]=i<16?p[i]:0;
  if(sc(54,fd,0x8913,(uint32_t)(uintptr_t)query,0,0,0)||!(query[16]&1)||(query[16]&8))continue;
  for(uint32_t i=16;i<32;i++)query[i]=0;
  if(sc(54,fd,0x8b01,(uint32_t)(uintptr_t)query,0,0,0)||!query[16])continue;
  if(++found>1)return 0;
  for(uint32_t i=0;i<16;i++)name[i]=(char)p[i];
 }
 return found==1;
}
static int send_bytes(uint32_t fd,const char*p,uint32_t bytes,uint64_t start){
 uint32_t done=0;while(done<bytes){if(!current(start))return 0;uint32_t n=sc(289,fd,(uint32_t)(uintptr_t)(p+done),bytes-done,0x4000,0,0);if(n==0xfffffffcu)continue;if(failed(n)||!n||n>bytes-done)return 0;done+=n;}return 1;
}
static int reply(uint32_t fd,const char*body,uint32_t bytes,int ok,uint64_t start){
 char head[192];uint32_t n=add(head,0,ok?"HTTP/1.1 200 OK\r\n":"HTTP/1.1 404 Not Found\r\n");
 n=add(head,n,"Connection: close\r\nContent-Type: application/json\r\nCache-Control: no-store\r\nContent-Length: ");n=digits(head,n,bytes);n=add(head,n,"\r\n\r\n");
 return send_bytes(fd,head,n,start)&&send_bytes(fd,body,bytes,start);
}
static int connection(uint32_t fd,const char*body,uint32_t bytes,uint64_t start){
 int32_t timeout[2]={0,200000};
 if(sc(294,fd,1,20,(uint32_t)(uintptr_t)timeout,sizeof(timeout),0)||sc(294,fd,1,21,(uint32_t)(uintptr_t)timeout,sizeof(timeout),0))return 0;
 char request[512];uint32_t have=0,head=0;
 while(have<sizeof(request)&&current(start)){
  uint32_t n=sc(3,fd,(uint32_t)(uintptr_t)(request+have),sizeof(request)-have,0,0,0);
  if(n==0xfffffffcu||n==0xfffffff5u)continue;
  if(failed(n)||!n||n>sizeof(request)-have)return 0;have+=n;
  for(uint32_t i=3;i<have;i++)if(request[i-3]=='\r'&&request[i-2]=='\n'&&request[i-1]=='\r'&&request[i]=='\n'){head=i+1;break;}
  if(head)break;
 }
 static const char path[]="GET /m10v/probe/v1/read HTTP/1.1\r\n";
 int valid=head>=sizeof(path)-1;
 for(uint32_t i=0;valid&&i<sizeof(path)-1;i++)if(request[i]!=path[i])valid=0;
 for(uint32_t i=0;valid&&i<head;i++)if(!request[i])valid=0;
 if(!valid){static const char error[]="{\"error\":\"unsupportedProbePath\"}";reply(fd,error,sizeof(error)-1,0,start);return 0;}
 return reply(fd,body,bytes,1,start);
}
static int serve_observation(const mc_probe_result*r){
 uint32_t fd=sc(281,2,1,0,0,0,0);if(failed(fd))return 7;
 char interface[16];int result=7;
 window_ms=r->sequence==1?45000:8000;
 uint64_t start=now_ms();if(!start)goto done;
 while(!discover_wifi(fd,interface)){
  if(!current(start))goto done;
  int32_t pause[2]={0,200000000};if(sc(162,(uint32_t)(uintptr_t)pause,0,0,0,0,0))goto done;
 }
 uint32_t length=0;while(length<16&&interface[length])length++;
 int enabled=1;
 if(sc(294,fd,1,25,(uint32_t)(uintptr_t)interface,length+1,0)||sc(294,fd,1,2,(uint32_t)(uintptr_t)&enabled,4,0))goto done;
 struct {uint16_t family;uint8_t port[2],ip[4],zero[8];} address={2,{0x49,0x37},{192,168,0,1},{0}};
 if(sc(282,fd,(uint32_t)(uintptr_t)&address,sizeof(address),0,0,0)||sc(284,fd,1,0,0,0,0)||sc(55,fd,4,0x800,0,0,0))goto done;
 char body[384];uint32_t n=add(body,0,"{\"schema\":\"m10v-read-probe/v1\",\"probeBuildId\":\"" MC_PROBE_BUILD_ID "\",\"targetBuildId\":\"" MC_TARGET_BUILD_ID "\",\"runId\":");
 n=digits(body,n,r->run_id);n=add(body,n,",\"round\":");n=digits(body,n,r->sequence);n=add(body,n,",\"value\":");n=digits(body,n,r->value);n=add(body,n,",\"packetTag\":");n=digits(body,n,r->packet_tag);n=add(body,n,",\"memoryWriteEnabled\":false,\"configurationWriteEnabled\":false}");
 for(unsigned attempts=0;attempts<64&&current(start);){
  struct{int32_t fd;int16_t events,revents;} poller={(int32_t)fd,1,0};
  uint32_t ready=sc(168,(uint32_t)(uintptr_t)&poller,1,100,0,0,0);
  if(ready==0xfffffffcu)continue;if(failed(ready))break;if(!ready)continue;
  uint32_t peer=sc(285,fd,0,0,0,0,0);if(peer==0xfffffffcu||peer==0xfffffff5u)continue;if(failed(peer))break;
  attempts++;int accepted=connection(peer,body,n,start);sc(6,peer,0,0,0,0,0);
  if(accepted){result=0;break;}
 }
 done:sc(6,fd,0,0,0,0,0);return result;
}
static int emit(const char*p,uint32_t bytes){
 uint32_t done=0,retries=0;
 while(done<bytes){uint32_t n=sc(4,1,(uint32_t)(uintptr_t)(p+done),bytes-done,0,0,0);if(n==0xfffffffcu&&retries++<3)continue;if(failed(n)||!n||n>bytes-done)return 0;done+=n;}
 return 1;
}
int mc_linux_main(void){
 uint32_t fd=sc(5,(uint32_t)(uintptr_t)"/dev/mem",0x101000,0,0,0,0); /* O_RDONLY | O_SYNC */
 int result=MC_PROBE_MEMORY;mc_probe_result observation;
 if(!failed(fd)){
  mc_probe_io io={&fd,read_camera};result=mc_probe_observe(&mc_target,&io,&observation);
  if(sc(6,fd,0,0,0,0,0))result=MC_PROBE_MEMORY;
 }
 if(!result)result=serve_observation(&observation);
 char output[96];uint32_t n=0;
 if(result){n=add(output,n,"MC_ERROR\n");n=number(output,n,(uint32_t)result);}
 else n=add(output,n,"MCP_READ_SERVED\n");
 if(!emit(output,n))return MC_PROBE_MEMORY;return result;
}
__attribute__((naked,noreturn)) void _start(void){__asm__ volatile("bl mc_linux_main\nmov r7,#1\nsvc 0\nb .");}
