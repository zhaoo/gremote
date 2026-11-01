import importlib.util,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
SPEC=importlib.util.spec_from_file_location('collect_camera_probe',ROOT/'scripts/collect_camera_probe.py')
COLLECTOR=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(COLLECTOR)
class Collector(unittest.TestCase):
 def frames(self):
  return [{'schema':'m10v-read-probe/v1','probeBuildId':'a'*16,'targetBuildId':'e78dd1d7','runId':123456,'round':i,'value':12345+17*i,'packetTag':0x678dd1d7,'configurationWriteEnabled':False,'memoryWriteEnabled':False} for i in range(1,17)]
 def manifest(self):return {'probeBuildId':'a'*16,'targetBuildId':'e78dd1d7','target':{'packetTag':0x678dd1d7}}
 def test_all_rounds_observed_without_granting_state_or_write_capabilities(self):
  r=COLLECTOR.verify_frames(self.frames(),self.manifest());self.assertEqual(r['status'],'READ_TRANSFER_OBSERVED')
  self.assertFalse(r['configurationWriteValidated']);self.assertFalse(r['bidirectionalRamValidated']);self.assertFalse(r['freshCameraStateValidated'])
 def test_partial_mixed_runs_wrong_binary_and_boolean_integers_rejected(self):
  for change in ['partial','run','build','target','value','boolean','write','duplicate']:
   f=self.frames()
   if change=='partial':f.pop()
   elif change=='run':f[-1]['runId']+=1
   elif change=='build':f[-1]['probeBuildId']='b'*16
   elif change=='target':f[-1]['packetTag']+=1
   elif change=='value':f[-1]['value']+=1
   elif change=='boolean':f[-1]['round']=True
   elif change=='write':f[-1]['memoryWriteEnabled']=0
   elif change=='duplicate':f[-1]=dict(f[0])
   with self.subTest(change=change),self.assertRaises(ValueError):COLLECTOR.verify_frames(f,self.manifest())
