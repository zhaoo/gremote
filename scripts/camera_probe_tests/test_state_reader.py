import ctypes as C,struct,subprocess,tempfile,unittest,zlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
READ=C.CFUNCTYPE(C.c_int,C.c_void_p,C.c_uint32,C.c_void_p,C.c_uint32)
class IO(C.Structure):_fields_=[('ctx',C.c_void_p),('read',READ)]
class Target(C.Structure):_fields_=[('guard',C.c_uint32),('owner_pointer',C.c_uint32),('heap_min',C.c_uint32),('heap_end',C.c_uint32),('cache_offset',C.c_uint32),('cache_bytes',C.c_uint32)]
class Result(C.Structure):_fields_=[('owner',C.c_uint32),('version',C.c_uint32),('state',C.c_uint8*184)]
class StateReader(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.tmp=tempfile.TemporaryDirectory();p=Path(cls.tmp.name)/'reader.so'
  source=ROOT/'native/camera_probe/state_reader.c'
  if source.exists():
   subprocess.run(['clang','-std=c11','-Wall','-Wextra','-Werror','-shared','-fPIC',str(source),'-o',str(p)],check=True,capture_output=True)
   cls.lib=C.CDLL(str(p));cls.lib.mc_state_observe.argtypes=[C.POINTER(Target),C.POINTER(IO),C.POINTER(Result)]
  else:cls.lib=None
 @classmethod
 def tearDownClass(cls):cls.tmp.cleanup()
 def observe(self,fault=None):
  self.assertIsNotNone(self.lib,'missing real state reader')
  target=Target(0x55063910,0x55063988,0x55804374,0x60000000,0x213c,0x4000);owner=0x55810000;cache=owner+target.cache_offset
  state=bytearray(184);struct.pack_into('<IHHI',state,0,0x5630314d,5,184,123)
  for i in range(10):struct.pack_into('<HBBBBBB',state,12+8*i,314+i%4,1,0,0,3,5,6)
  # Preserve every byte including newest slot and reserved effect fields.
  state[92:96]=bytes([2,3,2,1]);state[96:176]=bytes(range(80));struct.pack_into('<I',state,176,1)
  struct.pack_into('<I',state,180,zlib.crc32(state[:180]))
  if fault=='crc':state[20]^=1
  if fault=='schema':struct.pack_into('<H',state,4,4)
  if fault=='pendingMigration':struct.pack_into('<I',state,176,35);struct.pack_into('<I',state,180,zlib.crc32(state[:180]))
  memory={};reads={}
  def put(at,data):
   for i,b in enumerate(data):memory[at+i]=b
  put(target.guard,struct.pack('<I',0 if fault=='uninitialized' else 1))
  put(target.owner_pointer,struct.pack('<I',0x5fffffff if fault=='bounds' else owner))
  put(cache,struct.pack('<II',0 if fault=='magic' else 0x3856504d,3 if fault=='busy' else 0 if fault=='unpublished' else 2));put(cache+8,state)
  @READ
  def read(ctx,at,out,n):
   if n>64:return 0
   reads[at]=reads.get(at,0)+1
   if fault=='io':return 0
   data=bytes(memory.get(at+i,0) for i in range(n))
   if reads[at]>1:
    if fault=='ownerChange' and at==target.owner_pointer:data=struct.pack('<I',owner+0x8000)
    if fault=='versionChange' and at==cache:data=struct.pack('<II',0x3856504d,4)
    if fault=='packetChange' and at==cache+8:data=bytes([data[0]^1])+data[1:]
   C.memmove(out,data,n);return 1
  out=Result();result=self.lib.mc_state_observe(C.byref(target),C.byref(IO(None,read)),C.byref(out))
  return result,out,state
 def test_reads_all_ten_slots_and_preserves_exact_bytes(self):
  code,out,state=self.observe();self.assertEqual(code,0);self.assertEqual(bytes(out.state),state);self.assertEqual(out.version,2)
 def test_rejects_unstable_invalid_or_unavailable_state_without_partial_output(self):
  for fault in ['crc','schema','pendingMigration','uninitialized','bounds','magic','busy','unpublished','io','ownerChange','versionChange','packetChange']:
   with self.subTest(fault=fault):
    code,out,_=self.observe(fault);self.assertNotEqual(code,0);self.assertEqual(bytes(out.state),bytes(184))
