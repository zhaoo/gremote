#!/usr/bin/env python3
"""Audit and bundle an OFFLINE film-workbench candidate; never install or publish."""
import argparse,hashlib,json,os,re,struct,zipfile,zlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def sha(value):return hashlib.sha256(value).hexdigest()
def need(ok,message):
 if not ok:raise ValueError(message)
def hash_field(value):return isinstance(value,str) and re.fullmatch('[a-f0-9]{64}',value) is not None
def archive(path,maximum):
 need(path.is_file() and path.stat().st_size<=maximum,'artifact missing or oversized')
 with zipfile.ZipFile(path)as z:
  info=z.infolist();names=[i.filename for i in info]
  need(len(names)==len(set(names)) and len(names)<=2560 and sum(i.file_size for i in info)<=maximum,'invalid archive size or duplicate files')
  for i in info:need(not i.flag_bits&1 and not i.filename.startswith('/') and '\\' not in i.filename and '..' not in i.filename.split('/') and (i.external_attr>>16)&0o170000!=0o120000,'unsafe archive entry')
  need(z.testzip() is None,'archive CRC mismatch');return {name:z.read(name)for name in names if not name.endswith('/')}
def audit_sd(data,renderer):
 need(len(data)>=4096 and data[:8] in (b'M10VSD1\0',b'M10VSD2\0'),'invalid SD header')
 version,total,count,size,model,flags=struct.unpack_from('<6I',data,8)
 need(version in (1,2) and data[:8]==(b'M10VSD1\0' if version==1 else b'M10VSD2\0') and total==len(data) and 1<=count<=256 and size==12288 and model==239 and flags==1 and len(data)==4096+count*size,'invalid SD identity')
 need(zlib.crc32(data[:4092])==struct.unpack_from('<I',data,4092)[0],'SD header CRC mismatch')
 ids=set()
 for index in range(count):
  stable,crc,enabled=struct.unpack_from('<3I',data,64+index*12);record=data[4096+index*size:4096+(index+1)*size]
  need(stable not in ids and (33<=stable<=288 or stable==289) and enabled==1 and stable==struct.unpack_from('<I',record,8)[0] and crc==struct.unpack_from('<I',record,size-4)[0] and crc==zlib.crc32(record[:-4]) and record[8448:8480].hex()==renderer,'SD record identity or CRC mismatch');ids.add(stable)
def package_candidate(apk,camera_receipt,out):
 apk,camera_receipt,out=Path(apk),Path(camera_receipt),Path(out)
 if out.exists():raise FileExistsError(out)
 need(camera_receipt.is_file() and camera_receipt.stat().st_size<=32768,'camera receipt missing or oversized')
 receipt=json.loads(camera_receipt.read_bytes());need(isinstance(receipt,dict),'invalid camera receipt')
 need(receipt.get('schema')=='m10v-companion-candidate/v1' and receipt.get('model')=='GR III','unsupported camera receipt identity')
 need(receipt.get('validation')=='offline-verified' and all(receipt.get(k) is False for k in ('installable','listenEnabled','cameraPassed')),'unproven camera acceptance status')
 caps=receipt.get('capabilities');need(isinstance(caps,dict) and set(caps)=={'readState','writeState','uploadFilm','captureEvidence'} and all(value is False for value in caps.values()),'unproven camera capabilities')
 for key in ('sourceFingerprint','serviceSourceFingerprint','configurationHash','candidateSha256','serviceSha256','registrySha256','catalogHash','rendererHash'):need(hash_field(receipt.get(key)),'missing hash in camera receipt: '+key)
 camera_zip=camera_receipt.parent/'candidate.zip';camera=archive(camera_zip,128*1024*1024)
 expected={'candidate/fwdc239b.bin','disabled-service/m10v-companion.elf','private/pairing.json','SD/M10V/FILMS.M10','RESTORE.txt','receipt.json','SHA256SUMS'}
 need(set(camera)==expected and json.loads(camera['receipt.json'])==receipt,'camera archive/receipt differs')
 need(isinstance(receipt.get('files'),dict),'invalid camera file manifest')
 need(set(receipt.get('files',{}))==expected-{'receipt.json','SHA256SUMS'},'camera file manifest differs')
 for name,meta in receipt['files'].items():need(meta=={'bytes':len(camera[name]),'sha256':sha(camera[name])},'camera file hash differs: '+name)
 sums={}
 for line in camera['SHA256SUMS'].decode('ascii').splitlines():
  digest,name=line.split('  ',1);need(name not in sums and name in camera and digest==sha(camera[name]),'camera SHA256SUMS differs');sums[name]=digest
 need(set(sums)==expected-{'SHA256SUMS'},'incomplete camera SHA256SUMS')
 need(sha(camera['candidate/fwdc239b.bin'])==receipt['candidateSha256'] and sha(camera['disabled-service/m10v-companion.elf'])==receipt['serviceSha256'],'camera candidate/service hash differs')
 need(camera['disabled-service/m10v-companion.elf'][:4]==b'\x7fELF','invalid service ELF')
 audit_sd(camera['SD/M10V/FILMS.M10'],receipt['rendererHash'])
 pairing=json.loads(camera['private/pairing.json'])
 need(isinstance(pairing,dict) and all(isinstance(pairing.get(k),str)for k in ('schema','model','instanceId','keyId','keyHex')) and type(pairing.get('protocol'))is int and set(pairing)=={'schema','protocol','model','instanceId','keyId','keyHex'} and pairing['schema']=='m10v.companion-pairing/v1' and pairing['protocol']==1 and pairing['model']=='GR III' and re.fullmatch('[a-f0-9]{32}',pairing['instanceId']) and hash_field(pairing['keyHex']) and sha(bytes.fromhex(pairing['keyHex']))[:32]==pairing['keyId'],'invalid private pairing identity')
 app=archive(apk,512*1024*1024);prefix='assets/flutter_assets/assets/films/'
 catalog=json.loads(app[prefix+'catalog.json']);source=app[prefix+'source-manifest.json'];source_meta=json.loads(source)
 need(catalog['rendererHash']==receipt['rendererHash'] and source_meta['rendererHash']==receipt['rendererHash'],'renderer identity differs')
 need(catalog['hash']==receipt['catalogHash'] and source_meta['catalogHash']==receipt['catalogHash'],'catalog identity differs')
 canonical=json.dumps({k:v for k,v in catalog.items()if k!='hash'},sort_keys=True,ensure_ascii=False,separators=(',',':')).encode()
 need(sha(canonical)==catalog['hash'],'catalog checksum differs')
 need(sha(app[prefix+'companion-v1.json'])==receipt['registrySha256'],'wire registry differs')
 marker=('GREMOTE_FILM_V1:'+receipt['rendererHash']+':'+receipt['catalogHash']+':'+sha(source)).encode()
 libraries={name:data for name,data in app.items()if re.fullmatch(r'lib/[A-Za-z0-9_-]+/libgremote_imaging\.so',name)}
 need(bool(libraries),'native film library missing')
 for name,data in libraries.items():need(data[:4]==b'\x7fELF' and re.findall(rb'GREMOTE_FILM_V1:[a-f0-9]{64}:[a-f0-9]{64}:[a-f0-9]{64}',data)==[marker],'native film/source identity differs: '+name)
 build_id=sha(apk.read_bytes()+camera['receipt.json'])[:16]
 manifest={'schema':'gremote-film-workbench-candidate/v1','buildId':build_id,'validation':'offline-verified','model':'GR III','cameraPassed':False,'wirelessReady':False,'reason':'residentOwnerCacheWakeupAndWifiAdapterUnproven','apkSha256':sha(apk.read_bytes()),'cameraArchiveSha256':sha(camera_zip.read_bytes()),'cameraReceiptSha256':sha(camera_receipt.read_bytes()),'catalogHash':receipt['catalogHash'],'rendererHash':receipt['rendererHash'],'registrySha256':receipt['registrySha256'],'appNativeSourceManifestSha256':sha(source),'nativeAbis':sorted(name.split('/')[1]for name in libraries),'m10vSourceRevision':source_meta.get('sourceRevision'),'sourceFingerprint':receipt['sourceFingerprint'],'serviceSourceFingerprint':receipt['serviceSourceFingerprint']}
 # Validate everything before creating the new private output directory.
 out.mkdir(parents=True,mode=0o700)
 def write(name,data):
  target=out/name;target.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
  with target.open('xb')as f:f.write(data)
  os.chmod(target,0o600)
 write('GRemote-film-workbench.apk',apk.read_bytes());write('camera-candidate.zip',camera_zip.read_bytes());write('private/pairing.json',camera['private/pairing.json'])
 write('manifest.json',(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n').encode())
 write('README.zh-CN.txt',('GRemote × M10V 离线测试候选 '+build_id+'\nApp 可测试试色、数字胶卷、联系印样及配方导入；相机无线桥仍缺少实际 owner/cache/wakeup/Wi-Fi 适配，不能视为无线可用版本。\n本包不会安装、启动、刷写或发布任何组件。不要安装其中的相机固件或把禁用服务加入 STARTUP；它们仅用于离线审计。保留现有固件与 SD 脚本。\nprivate/pairing.json 是私有配对密钥，仅供本人手机导入；不要公开分享整个包。公开反馈只提供 buildId 和脱敏 manifest。\n所有设备性能、兼容性与无线写入验收均未完成。请按验收清单区分离线检查与后续具备真实桥接后的设备检查。\n').encode())
 acceptance=ROOT/'docs/testing/film-workbench-acceptance.md'
 if acceptance.exists():write('ACCEPTANCE.md',acceptance.read_bytes())
 evidence=ROOT/'docs/testing/film-workbench-source-manifest.json'
 if evidence.exists():write('source-manifest.json',evidence.read_bytes())
 files=sorted(p for p in out.rglob('*')if p.is_file());write('SHA256SUMS',(''.join(sha(p.read_bytes())+'  '+p.relative_to(out).as_posix()+'\n'for p in files)).encode())
 return manifest
if __name__=='__main__':
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--apk',required=True);parser.add_argument('--camera-receipt',required=True);parser.add_argument('--out',required=True);args=parser.parse_args()
 try:print(json.dumps(package_candidate(args.apk,args.camera_receipt,args.out),ensure_ascii=False))
 except (ValueError,KeyError,OSError,zipfile.BadZipFile)as error:parser.exit(1,'Candidate audit rejected: '+str(error)+'\n')
