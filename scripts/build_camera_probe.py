#!/usr/bin/env python3
"""Build a firmware-bound SD read probe. Never install or enable scripts."""
import argparse,hashlib,json,os,shutil,struct,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
TARGET_PATH=ROOT/'native/camera_probe/target-gr3-210.json'
def sha(b):return hashlib.sha256(b).hexdigest()
def need(ok,message):
 if not ok:raise ValueError(message)
def ttl_script(tag):
 lines=["; Standalone probe body only. Inspect existing startup before enabling.",
  "filesearch 'C:\\SCRIPT\\MCP1101\\RESULT.TXT'","if result != 0 goto mcp_already_run",
  "filesearch 'C:\\SCRIPT\\MCP1101\\TRACE.TXT'","if result != 0 goto mcp_already_run",
  "intdim mcprobe 16","random mcp_runid 1073741822","mcp_runid = mcp_runid + 1",
  f"mcprobe[0] = {0x4d435031}","mcprobe[1] = 1","mcprobe[2] = mcp_runid",f"mcprobe[5] = {tag}","mcprobe[6] = 0"]
 for i in range(7,16):lines.append(f'mcprobe[{i}] = {0x11ae00+i}')
 lines += ["filecreate mcp_trace 'C:\\SCRIPT\\MCP1101\\TRACE.TXT'","if mcp_trace < 0 goto mcp_end",
  "mpause 2000","sendln 'lcmd_resp on'","mcp_failure = 10","mcp_dispatches = 0","mcp_pass = 1",":mcp_pass_start","mcp_sequence = 1",":mcp_round",
  "if mcp_sequence > 16 goto mcp_pass_done","mcprobe[3] = mcp_sequence","mcprobe[4] = 12345 + mcp_sequence * 17",
  "inputstr = ''","sendln 'lcmd sh /media/storage1/SCRIPT/MCP1101/PROBE.SH'",
  "mcp_dispatches = mcp_dispatches + 1","mcp_command_result = result","strcopy inputstr 1 200 mcp_command_text",
  "int2str mcp_line mcp_sequence","filewriteln mcp_trace mcp_line","filewriteln mcp_trace mcp_command_text",
  "int2str mcp_line mcp_command_result","filewriteln mcp_trace mcp_line"]
 for i in range(7,16):lines += [f'if mcprobe[{i}] <> {0x11ae00+i} goto mcp_report']
 lines += ["mcp_sequence = mcp_sequence + 1","mpause 500","goto mcp_round",":mcp_pass_done","if mcp_pass >= 3 goto mcp_success","mcp_pass = mcp_pass + 1","goto mcp_pass_start",":mcp_success","mcp_failure = 0",":mcp_report",
  "fileclose mcp_trace","filecreate mcp_report 'C:\\SCRIPT\\MCP1101\\RESULT.TXT'","if mcp_report < 0 goto mcp_end",
  "filewriteln mcp_report 'MCP_READ_PROBE_V2'","int2str mcp_line mcp_runid","filewriteln mcp_report mcp_line","int2str mcp_line mcp_sequence","filewriteln mcp_report mcp_line","int2str mcp_line mcp_failure","filewriteln mcp_report mcp_line","int2str mcp_line mcp_dispatches","filewriteln mcp_report mcp_line","fileclose mcp_report",":mcp_end","end",":mcp_already_run","dispstr 'MCP_PROBE_ALREADY_RUN'","end"]
 return '\r\n'.join(lines)+'\r\n'
SH='''#!/bin/sh
# No Linux SD writes, no background process. Only stdout diagnostics.
/media/storage1/SCRIPT/MCP1101/PROBE.BIN
status=$?
echo MCP_LCMD_EXIT_$status
exit 0
'''
README = r"""M10V 跨域只读网络探针 · MCP1

目标：当前已验证的 GR III 2.10 调试固件 e78dd1d7。
本包不提供机内设置写入，不开放App装卷，不更换固件或安装Hook。
Linux仅以O_RDONLY/PROT_READ读取脚本临时数组，关闭/dev/mem后只在经核实的相机Wi-Fi接口192.168.0.1:18743短时响应GET /m10v/probe/v1/read。
它通过SIOCGIFCONF/IFF_UP/SIOCGIWNAME核对接口，再SO_BINDTODEVICE并绑定指定IP；无法核实就不监听。
无配对密钥；只返回脚本自己的run_id、轮次及固定校验数据，不读取用户相机设置或照片。此诊断接口不是经过认证的生产API。
Linux不写RAM或SD文件，没有后台驻留进程。每遍第一轮最多等待45秒，其余每轮8秒；正确GET一次后退出。相同run_id整组发布3遍，最多48次调用，以便早期Linux尚未挂载时后续遍补回缺轮；仍不保证启动成功。无采集器时整组最多约9分钟，不留后台进程。其他App的请求返回404且不会占用本轮有效响应。

请先不要自行启用
本包不包含 STARTUP.TTL、ModeSet 或 DEVELOP.MOD。不要覆盖现有 STARTUP.TTL。
启用SD脚本属于持久设置，先检查原卡脚本、现有插件及该开关，再准备最小、可回退的单独启动方案。本次构建不会替你开启它。
需要相机关机后用读卡器连接SD卡，先只读检查SCRIPT/STARTUP.TTL。探针本体含end，数组会占用解释器表，因此不能盲目插入原有驻留脚本前后；具体启动改动必须另行核对。
目标目录SCRIPT/MCP1101须是本工具自己的新目录。已有内容先备份，不整目录替换SCRIPT或删除其他插件。

手机侧准备（Linux不写SD回执）
手机通过USB连接电脑并允许调试，保持/重新连接相机Wi-Fi。
电脑先启动采集器，再按核对后的单独探针启动方案开机；采集器需赶上第一轮，漏轮不会被补算通过。
python3 tools/collect_camera_probe.py --adb /opt/homebrew/share/android-commandlinetools/platform-tools/adb --serial 手机USB序列号 --manifest manifest.json --out 新的手机采集.json
采集器最多等待600秒，响应体上限2048字节，按run_id、probeBuildId、序号、输入校验全部16个独立响应；同一轮不会重复计数，证据可跨同一run_id的多个遍历。采集完成后探针仍会完成剩余有界遍历，可待脚本结束或相机关机后撤除；关机后没有驻留代码。
不自动修改App或机身配置。使用的是固定诊断路径，原App的装卷按钮仍不可用。

结果与回传
回传电脑采集JSON，以及卡上SCRIPT/MCP1101/RESULT.TXT、TRACE.TXT（如有）。不需要照片、存档、Wi-Fi密码或配对文件。
TRACE仅由RTOS文件API写入每轮lcmd的有限返回信息，不是Linux文件写入。
python3 tools/read_camera_probe_result.py /实际路径/RESULT.TXT
RESULT V2中sequence=17、failure=0且dispatches=48只表示脚本发布了3遍共48次请求（16个不同轮次）（REQUESTS_PUBLISHED），不证明Linux或网络成功。
只有手机采集器收到同一run_id的全部16轮匹配响应才记录READ_TRANSFER_OBSERVED；这仍不证明双向RAM写入、持续缓存一致性、最新相机状态、设置所有者、文件系统提交或性能。
缺失/截断日志不能当通过。有RESULT或TRACE时脚本不自动重跑；重测前先备份本探针整个目录，再按新的测试安排处理自有输出。

撤除
相机关机后，仅撤掉为本次探针准备的启动改动和SCRIPT/MCP1101自有文件，恢复备份。不要删除整个SCRIPT或用全局scripts-off包停掉其他插件。
删掉文件不代表恢复脚本持久设置；若此次启用了该开关，应依据已核对的原状态单独恢复。

证据边界与来源
电脑上的固件包以SHA256绑定；设备运行时仅核对3段指令和数组布局，不是整个固件/全部Hook身份认证。
TTL解释器、Linux内核、无线ioctl及网络绑定都需实机验证，主机/ARM模拟不能替代。
目标布局和同步lcmd机制参考GRKit 固定checkout f62cd016298c97a1cfc3427b5cfeaf68780e7068（不安装其runtime）。
TTL语法参考：https://teratermproject.github.io/manual/5/en/macro/command/random.html 、https://teratermproject.github.io/manual/5/en/macro/command/intdim.html；相机实际解释器仍须独立验证。
"""
def audit_elf(data):
 need(data[:7]==b'\x7fELF\x01\x01\x01','expected little-endian ELF32')
 need(struct.unpack_from('<H',data,18)[0]==40,'expected ARM ELF')
 off=struct.unpack_from('<I',data,28)[0];size,count=struct.unpack_from('<HH',data,42)
 need(size==32 and count<=16 and off+size*count<=len(data),'invalid program headers')
 for i in range(count):
  typ=struct.unpack_from('<I',data,off+i*size)[0];need(typ not in (2,3),'dynamic ELF not allowed')
  flags=struct.unpack_from('<I',data,off+i*size+24)[0];need(not(flags&1 and flags&2),'writable executable segment not allowed')
 need(b'/dev/mem\0' in data,'missing read probe device')
def build_probe(firmware,receipt,m10v_source,out):
 firmware,receipt,m10v_source,out=map(Path,(firmware,receipt,m10v_source,out))
 if out.exists():raise FileExistsError(out)
 target=json.loads(TARGET_PATH.read_text());need(firmware.stat().st_size==target['firmwareBytes'],'firmware size differs')
 with firmware.open('rb')as file:data=file.read(target['firmwareBytes']+1)
 need(sha(data)==target['firmwareSha256'],'firmware identity differs')
 need(receipt.stat().st_size<=2*1024*1024,'receipt too large');meta=json.loads(receipt.read_text())
 need(meta.get('candidate_sha256')==target['firmwareSha256'] and meta.get('model')=='GR III' and meta.get('debug_mode') is True and meta.get('debug_log',{}).get('build_id')==target['buildId'],'receipt identity differs')
 for name,h in target['decoderFiles'].items():need(sha((m10v_source/name).read_bytes())==h,'decoder source differs: '+name)
 script="import{readFileSync}from'node:fs';import{decodeFrameMap}from'./node/gr3-frames.mjs';const b=readFileSync(process.argv[1]),d=decodeFrameMap(b,b.readUInt32LE(b.length-8)).decoded,r=d.subarray(0x10870,0x10870+d.readUInt32LE(0x1086c));const a=JSON.parse(process.argv[2]);process.stdout.write(JSON.stringify(a.map(address=>({address,hex:r.subarray(address-0x53000000,address-0x53000000+16).toString('hex')}))));"
 anchors=json.loads(subprocess.check_output(['node','--input-type=module','-e',script,str(firmware.resolve()),json.dumps(target['romAnchors'])],cwd=m10v_source,text=True))
 need(all(len(a['hex'])==32 for a in anchors),'anchor outside ROM')
 bound={k:target[k] for k in ['arrayCount','arrayTable','heapMin','heapEnd']};bound.update({'anchors':anchors,'packetTag':int(target['buildId'],16)&0x7fffffff})
 source_files=['native/camera_probe/probe.h','native/camera_probe/probe.c','native/camera_probe/linux_main.c','native/camera_probe/target-gr3-210.json','scripts/build_camera_probe.py','scripts/read_camera_probe_result.py','scripts/collect_camera_probe.py']
 source_hashes={name:sha((ROOT/name).read_bytes()) for name in source_files}
 probe_id=sha(json.dumps(source_hashes,sort_keys=True).encode())[:16]
 header='#include "probe.h"\n#define MC_PROBE_BUILD_ID "'+probe_id+'"\n#define MC_TARGET_BUILD_ID "'+target['buildId']+'"\nstatic const mc_probe_target mc_target={'+','.join(str(bound[k])+'u' for k in ['arrayCount','arrayTable','heapMin','heapEnd','packetTag'])+',{' + ','.join('{'+str(a['address'])+'u,{'+','.join(str(b) for b in bytes.fromhex(a['hex']))+'}}' for a in anchors)+'}};\n'
 clang=shutil.which('clang');linker=shutil.which('ld.lld');need(clang and linker,'clang and ld.lld required')
 with tempfile.TemporaryDirectory(prefix='m10v-read-probe-') as tmp:
  p=Path(tmp);(p/'target_generated.h').write_text(header);objects=[]
  for source in ['probe.c','linux_main.c']:
   obj=p/(source+'.o');subprocess.run([clang,'--target=armv7-linux-gnueabi','-mcpu=cortex-a9','-marm','-mfloat-abi=soft','-Os','-ffreestanding','-fno-builtin','-fno-stack-protector','-fno-unwind-tables','-fno-asynchronous-unwind-tables','-ffunction-sections','-fdata-sections','-Wall','-Wextra','-Werror','-I',str(ROOT/'native/camera_probe'),'-I',str(p),'-c',str(ROOT/'native/camera_probe'/source),'-o',str(obj)],check=True,capture_output=True);objects.append(str(obj))
  elf=p/'probe.elf';subprocess.run([linker,'-m','armelf_linux_eabi','--entry=_start','--gc-sections','--build-id=none','-z','noexecstack','-Ttext=0x10000',*objects,'-o',str(elf)],check=True,capture_output=True)
  binary=elf.read_bytes();audit_elf(binary)
 out.mkdir(parents=True,mode=0o700);folder=out/'SD/SCRIPT/MCP1101';folder.mkdir(parents=True)
 (folder/'PROBE.BIN').write_bytes(binary);os.chmod(folder/'PROBE.BIN',0o700)
 (folder/'PROBE.TTL').write_bytes(ttl_script(bound['packetTag']).encode('ascii'));(folder/'PROBE.SH').write_text(SH)
 manifest={'schema':'m10v-lcmd-read-probe/v1','targetBuildId':target['buildId'],'targetFirmwareSha256':target['firmwareSha256'],'target':bound,'elfSha256':sha(binary),'memoryWriteEnabled':False,'networkListenerEnabled':True,'configurationWriteEnabled':False,'cameraPassed':False,'validation':'HOST_AND_ARM_ONLY','runtimeIdentityEvidence':'threePinnedCodeWindowsOnly','rounds':16,'publicationPasses':3,'sourceFiles':source_hashes}
 manifest['probeBuildId']=probe_id
 (out/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
 (out/'README.zh-CN.txt').write_text(README)
 (out/'tools').mkdir();shutil.copy2(ROOT/'scripts/read_camera_probe_result.py',out/'tools/read_camera_probe_result.py');shutil.copy2(ROOT/'scripts/collect_camera_probe.py',out/'tools/collect_camera_probe.py')
 files=sorted(p for p in out.rglob('*') if p.is_file())
 (out/'SHA256SUMS').write_text(''.join(sha(p.read_bytes())+'  '+p.relative_to(out).as_posix()+'\n' for p in files))
 return manifest
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--firmware',required=True);p.add_argument('--receipt',required=True);p.add_argument('--m10v-source',required=True);p.add_argument('--out',required=True);a=p.parse_args()
 m=build_probe(a.firmware,a.receipt,a.m10v_source,a.out);print(json.dumps({'elfSha256':m['elfSha256'],'cameraPassed':m['cameraPassed']}))
