import base64,hashlib,json,tempfile,unittest,zipfile,struct,zlib
from pathlib import Path
from package_film_workbench_candidate import package_candidate
ROOT=Path(__file__).resolve().parents[1]
def sha(b):return hashlib.sha256(b).hexdigest()
class CandidatePackage(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name);self.apk=self.root/'app.apk';self.camera=self.root/'camera';self.camera.mkdir();self.receipt=self.camera/'receipt.json'
  self.catalog=(ROOT/'assets/films/catalog.json').read_bytes();self.contract=(ROOT/'assets/films/companion-v1.json').read_bytes();self.source=(ROOT/'assets/films/source-manifest.json').read_bytes();catalog=json.loads(self.catalog)
  marker=f"GREMOTE_FILM_V1:{catalog['rendererHash']}:{catalog['hash']}:{sha(self.source)}".encode();self.library=b'\x7fELF'+marker+b'\0'
  self.pair={'schema':'m10v.companion-pairing/v1','protocol':1,'model':'GR III','instanceId':'01'*16,'keyId':sha(bytes(range(32)))[:32],'keyHex':bytes(range(32)).hex()}
  film=json.loads((ROOT/'test/fixtures/custom-film.m10vfilm').read_bytes());record=base64.b64decode(film['recordBase64']);header=bytearray(4096);header[:8]=b'M10VSD2\0';struct.pack_into('<6I',header,8,2,4096+len(record),1,12288,239,1);struct.pack_into('<3I',header,64,79,zlib.crc32(record[:-4]),1);struct.pack_into('<I',header,4092,zlib.crc32(header[:4092]));sd=bytes(header)+record
  self.files={'candidate/fwdc239b.bin':b'fixture firmware','disabled-service/m10v-companion.elf':b'\x7fELFfixture','private/pairing.json':json.dumps(self.pair).encode(),'SD/M10V/FILMS.M10':sd,'RESTORE.txt':b'offline fixture'}
  self.meta={'schema':'m10v-companion-candidate/v1','model':'GR III','sourceFingerprint':'a'*64,'serviceSourceFingerprint':'b'*64,'configurationHash':'c'*64,'candidateSha256':sha(self.files['candidate/fwdc239b.bin']),'serviceSha256':sha(self.files['disabled-service/m10v-companion.elf']),'serviceBuildId':'b'*24,'registrySha256':sha(self.contract),'catalogHash':catalog['hash'],'rendererHash':catalog['rendererHash'],'installable':False,'listenEnabled':False,'cameraPassed':False,'validation':'offline-verified','capabilities':dict.fromkeys(['readState','writeState','uploadFilm','captureEvidence'],False)}
  self.write_apk();self.write_camera()
 def write_apk(self,*,library=None,catalog=None):
  with zipfile.ZipFile(self.apk,'w')as z:
   for name,data in {'assets/flutter_assets/assets/films/catalog.json':catalog or self.catalog,'assets/flutter_assets/assets/films/companion-v1.json':self.contract,'assets/flutter_assets/assets/films/source-manifest.json':self.source,'lib/arm64-v8a/libgremote_imaging.so':self.library if library is None else library}.items():z.writestr(name,data)
 def write_camera(self):
  self.meta['files']={name:{'bytes':len(data),'sha256':sha(data)}for name,data in self.files.items()};self.receipt.write_text(json.dumps(self.meta));rows={**self.files,'receipt.json':self.receipt.read_bytes()};rows['SHA256SUMS']=(''.join(sha(data)+'  '+name+'\n'for name,data in rows.items())).encode()
  with zipfile.ZipFile(self.camera/'candidate.zip','w')as z:
   for name,data in rows.items():z.writestr(name,data)
 def package(self,name='out'):return package_candidate(self.apk,self.receipt,self.root/name)
 def test_private_offline_bundle_has_hashes_and_no_key_in_public_manifest(self):
  receipt=self.package();out=self.root/'out';self.assertEqual(receipt['validation'],'offline-verified');self.assertFalse(receipt['cameraPassed']);self.assertNotIn(self.pair['keyHex'],json.dumps(receipt));self.assertEqual((out/'private/pairing.json').stat().st_mode&0o777,0o600)
  for line in (out/'SHA256SUMS').read_text().splitlines():digest,name=line.split('  ',1);self.assertEqual(sha((out/name).read_bytes()),digest)
  with self.assertRaises(FileExistsError):self.package()
 def test_candidate_rejects_mismatched_renderer(self):
  self.meta['rendererHash']='0'*64;self.write_camera()
  with self.assertRaisesRegex(ValueError,'renderer|identity'):self.package()
  self.assertFalse((self.root/'out').exists())
 def test_missing_native_marker_or_stale_native_source_rejects(self):
  for library in [b'\x7fELFno marker',self.library.replace(sha(self.source).encode(),b'0'*64)]:
   self.write_apk(library=library)
   with self.assertRaisesRegex(ValueError,'native|identity'):self.package()
 def test_wrong_model_unknown_or_forged_camera_acceptance_rejects(self):
  original=dict(self.meta)
  for key,value in [('model','GR IIIx'),('schema','old'),('cameraPassed',True),('validation','accepted'),('listenEnabled',True),('capabilities',dict.fromkeys(['readState','writeState','uploadFilm','captureEvidence'],0))]:
   self.meta={**original,key:value};self.write_camera()
   with self.assertRaises(ValueError):self.package()
 def test_corrupt_camera_archive_and_registry_drift_reject(self):
  self.files['candidate/fwdc239b.bin']=b'changed';self.write_camera()
  with self.assertRaises(ValueError):self.package()
  self.files['candidate/fwdc239b.bin']=b'fixture firmware';self.meta['registrySha256']='0'*64;self.write_camera()
  with self.assertRaisesRegex(ValueError,'registry'):self.package()
