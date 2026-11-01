import importlib.util,json,struct,tempfile,unittest,hashlib,os
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
BASE=Path(os.environ.get('M10V_PROBE_BASE','/Users/zhaoo/.codex/worktrees/film-companion/diagnostic-20261101'))
SPEC=importlib.util.spec_from_file_location('build_camera_probe',ROOT/'scripts/build_camera_probe.py')
BUILDER=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(BUILDER)

class Package(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  if not (BASE/'candidate-core-r2/fwdc239b.bin').is_file():raise unittest.SkipTest('Set M10V_PROBE_BASE to the exact private e78dd1d7 candidate directory')
  cls.tmp=tempfile.TemporaryDirectory();cls.path=Path(cls.tmp.name);cls.out=cls.path/'probe'
  cls.manifest=BUILDER.build_probe(BASE/'candidate-core-r2/fwdc239b.bin',BASE/'candidate-core-r2/M10V-build-receipt.json',BASE/'source',cls.out)
 @classmethod
 def tearDownClass(cls):cls.tmp.cleanup()
 def test_wrong_firmware_and_existing_output_refused_without_mutation(self):
  bad=self.path/'bad.bin';bad.write_bytes(b'wrong')
  with self.assertRaises(ValueError):BUILDER.build_probe(bad,BASE/'candidate-core-r2/M10V-build-receipt.json',BASE/'source',self.path/'bad-out')
  self.assertFalse((self.path/'bad-out').exists())
  with self.assertRaises(FileExistsError):BUILDER.build_probe(bad,bad,bad,self.out)
 def test_scripts_are_bounded_and_never_replace_shared_startup_or_enable_modeset(self):
  files=[p.relative_to(self.out).as_posix() for p in self.out.rglob('*') if p.is_file()]
  self.assertFalse(any(Path(p).name.upper() in ['STARTUP.TTL','DEVELOP.MOD'] for p in files))
  ttl=(self.out/'SD/SCRIPT/MCP1101/PROBE.TTL').read_text()
  self.assertIn('intdim mcprobe 16',ttl);self.assertIn('random mcp_runid 1073741822',ttl)
  self.assertIn('if mcp_sequence > 16 goto mcp_success',ttl)
  self.assertIn('lcmd sh /media/storage1/SCRIPT/MCP1101/PROBE.SH',ttl)
  self.assertNotIn('setdebug',ttl.lower());self.assertNotIn('SCRIPT_EN_MODE',ttl)
  sh=(self.out/'SD/SCRIPT/MCP1101/PROBE.SH').read_text()
  self.assertNotIn('nohup',sh);self.assertNotIn(' &',sh);self.assertNotIn('>',sh)
  self.assertTrue((self.out/'tools/collect_camera_probe.py').is_file())
  self.assertFalse(self.manifest['memoryWriteEnabled']);self.assertFalse(self.manifest['cameraPassed'])
 def test_package_has_complete_checksums_and_manual_activation_documentation(self):
  sums=(self.out/'SHA256SUMS').read_text().splitlines()
  actual={p.relative_to(self.out).as_posix() for p in self.out.rglob('*') if p.is_file()}-{'SHA256SUMS'}
  listed=set()
  for line in sums:
   digest,name=line.split('  ',1);listed.add(name)
   self.assertEqual(hashlib.sha256((self.out/name).read_bytes()).hexdigest(),digest)
  self.assertEqual(actual,listed)
  readme=(self.out/'README.zh-CN.txt').read_text()
  self.assertIn('不提供机内设置写入',readme)
  self.assertIn('不要覆盖现有 STARTUP.TTL',readme)
  self.assertTrue((self.out/'tools/read_camera_probe_result.py').is_file())
 def test_arm_elf_has_no_dynamic_dependencies_and_executes_with_readonly_maps(self):self.run_elf()
 def test_arm_failures_close_readonly_mapping_and_never_emit_success(self):
  for fault in ['cache','identity','mmap','wifi','address','ambiguous','timeout']:
   with self.subTest(fault=fault):self.run_elf(fault)
 def test_old_app_requests_cannot_consume_the_probe_round(self):self.run_elf('oldClient')
 def test_write_method_cannot_consume_the_probe_round(self):self.run_elf('writeClient')
 def run_elf(self,fault=None):
  from unicorn import Uc,UC_ARCH_ARM,UC_MODE_ARM,UC_HOOK_INTR,UC_HOOK_MEM_WRITE,UC_PROT_READ
  from unicorn import arm_const as A
  data=(self.out/'SD/SCRIPT/MCP1101/PROBE.BIN').read_bytes();u=Uc(UC_ARCH_ARM,UC_MODE_ARM)
  phoff=struct.unpack_from('<I',data,28)[0];phsize,phnum=struct.unpack_from('<HH',data,42)
  mapped=set()
  for i in range(phnum):
   typ,off,va,_,size,mem,flags,align=struct.unpack_from('<8I',data,phoff+i*phsize)
   self.assertNotIn(typ,[2,3])
   if typ!=1:continue
   for page in range(va&~4095,(va+mem+4095)&~4095,4096):
    if page not in mapped:u.mem_map(page,4096);mapped.add(page)
   u.mem_write(va,data[off:off+size])
  u.mem_map(0x7e000000,0x10000);u.reg_write(A.UC_ARM_REG_SP,0x7e00fff0)
  target=self.manifest['target'];physical={}
  def put(at,b):
   for i,v in enumerate(b):physical[at+i]=v
  for anchor in target['anchors']:put(anchor['address'],bytes.fromhex(anchor['hex']))
  if fault=='identity':physical[target['anchors'][0]['address']]^=1
  pointer=0x55810000
  put(target['arrayCount'],struct.pack('<H',1));put(target['arrayTable'],struct.pack('<II',16,pointer))
  packet=[0x4d435031,1,123456,2,12379,target['packetTag'],0]+[0x11ae00+i for i in range(7,16)]
  put(pointer,struct.pack('<16I',*packet));out=bytearray();exit_code=[];memory_maps=[];responses=[];requests=[];reads=[0];clock=[0];bound=[];closed=[]
  def syscall(uc,number,ctx):
   nr=uc.reg_read(A.UC_ARM_REG_R7);args=[uc.reg_read(getattr(A,f'UC_ARM_REG_R{i}')) for i in range(6)]
   if nr==5:
    path=bytes(uc.mem_read(args[0],16)).split(b'\0')[0]
    self.assertEqual(path,b'/dev/mem');self.assertEqual(args[1]&3,0);result=7
   elif nr==192:
    _,length,prot,flags,fd,page=args;self.assertEqual(prot,1);self.assertEqual(fd,7);self.assertLessEqual(length,8192)
    if fault=='mmap':uc.reg_write(A.UC_ARM_REG_R0,0xfffffff3);return
    base=0x10000000;uc.mem_map(base,length)
    payload=bytes(physical.get((page<<12)+i,0) for i in range(length));uc.mem_write(base,payload);uc.mem_protect(base,length,UC_PROT_READ)
    memory_maps.append((base,length));result=base
   elif nr==91:uc.mem_unmap(args[0],args[1]);memory_maps.remove((args[0],args[1]));result=0
   elif nr==0xf0002:result=0xffffffff if fault=='cache' else 0
   elif nr==6:self.assertIn(args[0],[7,9,10]);closed.append(args[0]);result=0
   elif nr==281:self.assertEqual(args[:3],[2,1,0]);result=9
   elif nr==54:
    self.assertEqual(args[0],9)
    if args[1]==0x8912:
     length,at=struct.unpack('<II',uc.mem_read(args[2],8));self.assertGreaterEqual(length,32)
     name=b'uap0'+b'\0'*12
     ip=bytes([10,0,0,1] if fault=='address' else [192,168,0,1])
     uc.mem_write(at,name+struct.pack('<H',2)+b'\0\0'+ip+b'\0'*8)
     if fault=='ambiguous':
      uc.mem_write(at+32,b'wlan0'+b'\0'*11+struct.pack('<H',2)+b'\0\0'+ip+b'\0'*8)
     uc.mem_write(args[2],struct.pack('<II',64 if fault=='ambiguous' else 32,at));result=0
    elif args[1]==0x8913:uc.mem_write(args[2]+16,struct.pack('<H',0x41));result=0
    elif args[1]==0x8b01:
     if fault=='wifi':result=0xffffffa1
     else:uc.mem_write(args[2]+16,b'IEEE 802.11\0');result=0
    else:self.fail('unexpected ioctl')
   elif nr==294:
    self.assertEqual(args[1],1)
    if args[2]==25:self.assertEqual(bytes(uc.mem_read(args[3],args[4])),b'uap0\0')
    else:self.assertIn(args[2],[2,20,21])
    result=0
   elif nr==282:
    self.assertEqual(args[0],9);address=bytes(uc.mem_read(args[1],16))
    self.assertEqual(address[:8],b'\x02\x00\x49\x37\xc0\xa8\x00\x01');bound.append(address);result=0
   elif nr==284:self.assertEqual(args[:2],[9,1]);result=0
   elif nr==55:self.assertEqual(args[:3],[9,4,0x800]);result=0
   elif nr==263:
    clock[0]+=2000 if fault=='timeout' else 1
    uc.mem_write(args[1],struct.pack('<ii',1+clock[0]//1000,(clock[0]%1000)*1000000));result=0
   elif nr==162:clock[0]+=200;result=0
   elif nr==168:
    fd,events,_=struct.unpack('<ihh',uc.mem_read(args[0],8));self.assertEqual(fd,9)
    uc.mem_write(args[0],struct.pack('<ihh',fd,events,0 if fault=='timeout' else 1));result=0 if fault=='timeout' else 1
   elif nr==285:
    self.assertEqual(args[0],9);path='/m10v/v1/capabilities' if fault=='oldClient' and not requests else '/m10v/probe/v1/read'
    method='POST' if fault=='writeClient' and not requests else 'GET'
    requests.append((method+' '+path+' HTTP/1.1\r\nHost: camera\r\n\r\n').encode());responses.append(bytearray());reads[0]=0;result=10
   elif nr==3:
    self.assertEqual(args[0],10);chunk=requests[-1][reads[0]:reads[0]+args[2]];uc.mem_write(args[1],chunk);reads[0]+=len(chunk);result=len(chunk)
   elif nr==289:
    self.assertEqual(args[0],10);self.assertEqual(args[3],0x4000);responses[-1].extend(uc.mem_read(args[1],args[2]));result=args[2]
   elif nr==4:self.assertEqual(args[0],1);out.extend(uc.mem_read(args[1],args[2]));result=args[2]
   elif nr==1:exit_code.append(args[0]);uc.emu_stop();return
   else:self.fail(f'unexpected syscall {nr}')
   uc.reg_write(A.UC_ARM_REG_R0,result)
  u.hook_add(UC_HOOK_INTR,syscall)
  entry=struct.unpack_from('<I',data,24)[0];u.emu_start(entry,0,count=1000000)
  self.assertEqual(memory_maps,[])
  if fault in ['cache','identity','mmap','wifi','address','ambiguous','timeout']:
   code=1 if fault=='identity' else 7 if fault in ['wifi','address','ambiguous','timeout'] else 6
   self.assertEqual(exit_code,[code]);self.assertIn(f'MC_ERROR\n{code}\n',out.decode())
   if fault in ['wifi','address','ambiguous']:self.assertEqual(bound,[])
  else:
   self.assertEqual(exit_code,[0]);self.assertEqual(len(bound),1)
   self.assertIn(b'200 OK',responses[-1])
   body=json.loads(bytes(responses[-1]).split(b'\r\n\r\n',1)[1])
   self.assertEqual(body['runId'],123456);self.assertEqual(body['round'],2);self.assertEqual(body['value'],12379)
   self.assertEqual(body['probeBuildId'],self.manifest['probeBuildId']);self.assertFalse(body['memoryWriteEnabled'])
   if fault in ['oldClient','writeClient']:self.assertIn(b'404',responses[0])
