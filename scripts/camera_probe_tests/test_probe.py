"""Execute the portable C reader against bounded sparse target memory."""
import ctypes,subprocess,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
HARNESS=r'''
#include "probe.h"
#include <string.h>
static mc_probe_target target;
static unsigned char memory[512];
static int mode,reads;
static int read_memory(void*ctx,uint32_t address,void*out,uint32_t length){
 (void)ctx;reads++;
 if(mode==14)return 0;
 if(mode==15&&reads==9)memory[64+8]^=1;
 if(mode==16&&reads==7)memory[0]=2;
 if(mode==13&&reads>6){uint32_t replacement=0x55805080;memcpy(memory+12,&replacement,4);}
 if(address<0x55805000||length>sizeof(memory)||address-0x55805000>sizeof(memory)-length)return 0;
 memcpy(out,memory+address-0x55805000,length);return 1;
}
int run_case(int which){
 mode=which;reads=0;memset(memory,0,sizeof(memory));memset(&target,0,sizeof(target));
 target.array_count=0x55805000;target.array_table=0x55805008;
 target.heap_min=0x55805000;target.heap_end=0x55805200;target.packet_tag=0x678dd1d7;
 for(unsigned i=0;i<MC_PROBE_ANCHORS;i++){target.anchors[i].address=0x55805100+i*16;for(unsigned j=0;j<16;j++)target.anchors[i].bytes[j]=(unsigned char)(i*16+j);memcpy(memory+256+i*16,target.anchors[i].bytes,16);}
 uint16_t count=1;memcpy(memory,&count,2);uint32_t descriptor[2]={MC_PROBE_WORDS,0x55805040};memcpy(memory+8,descriptor,8);
 uint32_t packet[MC_PROBE_WORDS]={MC_PROBE_MAGIC,1,123456,2,12379,0x678dd1d7,0};
 for(unsigned i=7;i<MC_PROBE_WORDS;i++)packet[i]=MC_PROBE_CANARY+i;
 if(mode==1)memory[256]^=1;
 if(mode==2){count=2;memcpy(memory,&count,2);}
 if(mode==3){descriptor[0]--;memcpy(memory+8,descriptor,8);}
 if(mode==4){descriptor[1]++;memcpy(memory+8,descriptor,8);}
 if(mode==5){descriptor[1]=target.heap_min-4;memcpy(memory+8,descriptor,8);}
 if(mode==6){descriptor[1]=0xfffffff0;memcpy(memory+8,descriptor,8);}
 if(mode==7)packet[0]^=1;
 if(mode==8)packet[3]=0;
 if(mode==9)packet[3]=17;
 if(mode==10)packet[4]++;
 if(mode==11)packet[5]++;
 if(mode==12)packet[15]++;
 if(mode==17)packet[2]=0;
 if(mode==18)packet[2]=0x40000000;
 if(mode==19)packet[6]=1;
 memcpy(memory+64,packet,sizeof(packet));
 uint8_t before[512];memcpy(before,memory,512);
 mc_probe_io io={0,read_memory};mc_probe_result result;
 int code=mc_probe_observe(&target,&io,&result);
 if(mode!=13&&mode!=15&&mode!=16&&memcmp(before,memory,512))return -100;
 if(code==0&&(result.run_id!=123456||result.sequence!=2||result.value!=12379))return -101;
 return code;
}
'''
class Probe(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.tmp=tempfile.TemporaryDirectory();p=Path(cls.tmp.name);(p/'h.c').write_text(HARNESS)
  subprocess.run(['clang','-std=c11','-Wall','-Wextra','-Werror','-shared','-fPIC','-I',str(ROOT/'native/camera_probe'),str(p/'h.c'),str(ROOT/'native/camera_probe/probe.c'),'-o',str(p/'probe.dylib')],check=True,capture_output=True)
  cls.lib=ctypes.CDLL(str(p/'probe.dylib'))
 @classmethod
 def tearDownClass(cls):cls.tmp.cleanup()
 def test_consistent_owned_packet_is_observed_without_writes(self):self.assertEqual(self.lib.run_case(0),0)
 def test_untrusted_identity_dimensions_addresses_and_packets_rejected(self):
  for mode in range(1,20):
   with self.subTest(mode=mode):self.assertGreater(self.lib.run_case(mode),0)
