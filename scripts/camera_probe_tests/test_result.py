import importlib.util,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
SPEC=importlib.util.spec_from_file_location('read_camera_probe_result',ROOT/'scripts/read_camera_probe_result.py')
READER=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(READER)
class Result(unittest.TestCase):
 def test_only_all_rounds_and_zero_failure_is_observed(self):
  result=READER.parse_result(b'MCP_READ_PROBE_V1\r\n123456\r\n17\r\n0\r\n')
  self.assertEqual(result['status'],'REQUESTS_PUBLISHED')
  self.assertFalse(result['configurationWriteValidated'])
  self.assertFalse(result['bidirectionalRamValidated'])
 def test_failure_stage_remains_failure(self):
  self.assertEqual(READER.parse_result(b'MCP_READ_PROBE_V1\n123\n8\n10\n')['status'],'PROBE_FAILED')
 def test_partial_oversized_wrong_schema_and_forged_success_rejected(self):
  for bad in [b'',b'x'*1025,b'WRONG\n1\n17\n0',b'MCP_READ_PROBE_V1\n0\n17\n0',b'MCP_READ_PROBE_V1\n1\n16\n0',b'MCP_READ_PROBE_V1\n1\n17\n2',b'MCP_READ_PROBE_V1\n1\n17\n0\nextra',b'MCP_READ_PROBE_V1\n1\n17.0\n0']:
   with self.subTest(bad=bad[:50]),self.assertRaises(ValueError):READER.parse_result(bad)
