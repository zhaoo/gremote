#!/usr/bin/env python3
"""Collect only the fixed diagnostic endpoint through an authorized Android USB link."""
import argparse,json,os,re,selectors,subprocess,time
from pathlib import Path
KEYS={'schema','probeBuildId','targetBuildId','runId','round','value','packetTag','configurationWriteEnabled','memoryWriteEnabled'}
def verify_frame(frame,manifest):
 if not isinstance(frame,dict) or set(frame)!=KEYS:raise ValueError('unexpected probe fields')
 if frame['schema']!='m10v-read-probe/v1' or frame['probeBuildId']!=manifest['probeBuildId'] or frame['targetBuildId']!=manifest['targetBuildId']:raise ValueError('wrong probe build')
 for k in ['runId','round','value','packetTag']:
  if type(frame[k])is not int:raise ValueError('probe integer required')
 if not 1<=frame['runId']<=0x3fffffff or not 1<=frame['round']<=16 or frame['value']!=12345+17*frame['round'] or frame['packetTag']!=manifest['target']['packetTag']:raise ValueError('invalid probe payload')
 if frame['configurationWriteEnabled'] is not False or frame['memoryWriteEnabled'] is not False:raise ValueError('unexpected write capability')
 return frame

def verify_frames(frames,manifest):
 if not isinstance(frames,list) or len(frames)!=16:raise ValueError('all sixteen distinct rounds are required')
 checked=[verify_frame(f,manifest) for f in frames]
 if len({f['runId'] for f in checked})!=1 or {f['round'] for f in checked}!=set(range(1,17)):raise ValueError('mixed run or missing round')
 return {'schema':'m10v-read-transfer-evidence/v1','status':'READ_TRANSFER_OBSERVED','probeBuildId':manifest['probeBuildId'],'runId':checked[0]['runId'],'roundsObserved':16,'configurationWriteValidated':False,'bidirectionalRamValidated':False,'freshCameraStateValidated':False,'evidence':'diagnostic HTTP observations; not authenticated camera capability proof'}

def request(adb,serial):
 args=[adb,'-s',serial,'shell',"curl --noproxy '*' --interface wlan0 --connect-timeout 1 --max-time 2 --max-filesize 2048 -sS http://192.168.0.1:18743/m10v/probe/v1/read"]
 process=subprocess.Popen(args,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL)
 selector=selectors.DefaultSelector();selector.register(process.stdout,selectors.EVENT_READ)
 data=bytearray();deadline=time.monotonic()+4
 try:
  while time.monotonic()<deadline:
   if not selector.select(min(.2,max(0,deadline-time.monotonic()))):continue
   chunk=os.read(process.stdout.fileno(),min(1024,2049-len(data)))
   if not chunk:break
   data.extend(chunk)
   if len(data)>2048:raise ValueError('oversized diagnostic response')
  else:raise TimeoutError('USB probe request timeout')
  code=process.wait(timeout=max(.1,deadline-time.monotonic()))
  if code:return None
  return json.loads(data.decode('utf8'))
 finally:
  selector.close();process.stdout.close()
  if process.poll()is None:process.kill();process.wait(timeout=2)

def collect(adb,serial,manifest,out,timeout=600):
 if not re.fullmatch('[A-Za-z0-9_.:-]{1,128}',serial):raise ValueError('invalid Android serial')
 if out.exists():raise FileExistsError(out)
 frames={};failure=None;result=None;end=time.monotonic()+timeout
 try:
  print('等待相机只读探针；不会修改相机设置。',flush=True)
  while time.monotonic()<end and len(frames)<16:
   try:frame=request(adb,serial)
   except (TimeoutError,subprocess.TimeoutExpired,json.JSONDecodeError,UnicodeDecodeError):frame=None
   if frame is not None:
    verify_frame(frame,manifest)
    if frames and frame['runId']!=next(iter(frames.values()))['runId']:raise ValueError('probe run changed')
    previous=frames.get(frame['round'])
    if previous is not None and previous!=frame:raise ValueError('conflicting repeated probe frame')
    if previous is None:
     frames[frame['round']]=frame;print(f"已收到 {len(frames)}/16，轮次 {frame['round']}",flush=True)
   time.sleep(.1)
  result=verify_frames(list(frames.values()),manifest)
 except KeyboardInterrupt:failure='interrupted'
 except (OSError,ValueError) as error:failure=str(error)
 payload={'schema':'m10v-probe-collection/v1','result':result,'error':failure,'frames':sorted(frames.values(),key=lambda f:f['round'])}
 out.parent.mkdir(parents=True,exist_ok=True)
 with out.open('x')as file:json.dump(payload,file,ensure_ascii=False,indent=2);file.write('\n')
 return payload

if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--adb',required=True);p.add_argument('--serial',required=True);p.add_argument('--manifest',type=Path,required=True);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
 try:
  if a.manifest.stat().st_size>65536:raise ValueError('oversized manifest')
  result=collect(a.adb,a.serial,json.loads(a.manifest.read_text()),a.out)
  print(json.dumps(result['result'] or {'error':result['error']},ensure_ascii=False));raise SystemExit(0 if result['result']else 1)
 except (OSError,ValueError)as error:p.exit(1,str(error)+'\n')
