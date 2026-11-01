#!/usr/bin/env python3
"""Read a user-supplied probe report. Never grant camera capabilities."""
import argparse,json,re
from pathlib import Path
PHASES={10:'scratch guard'}
def parse_result(data):
 if not data or len(data)>1024:raise ValueError('missing or oversized probe result')
 try:lines=data.decode('ascii').splitlines()
 except UnicodeDecodeError as error:raise ValueError('invalid probe encoding') from error
 if len(lines)!=4 or lines[0]!='MCP_READ_PROBE_V1' or any(not re.fullmatch('[0-9]{1,10}',v) for v in lines[1:]):raise ValueError('invalid probe result')
 run,sequence,failure=map(int,lines[1:])
 if not 1<=run<=0x3fffffff or not (failure==0 and sequence==17 or failure in PHASES and 1<=sequence<=16):raise ValueError('invalid round/failure combination')
 return {'schema':'m10v-read-probe-result/v1','runId':run,'status':'PROBE_FAILED' if failure else 'REQUESTS_PUBLISHED','requestsPublished':sequence-1,'failurePhase':PHASES.get(failure),'readDirectionValidated':False,'configurationWriteValidated':False,'bidirectionalRamValidated':False,'freshCameraStateValidated':False,'evidence':'user-supplied text; not authenticated capability proof'}
if __name__=='__main__':
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('result',type=Path);args=parser.parse_args()
 try:
  if args.result.stat().st_size>1024:raise ValueError('oversized probe result')
  print(json.dumps(parse_result(args.result.read_bytes()),ensure_ascii=False,indent=2))
 except (OSError,ValueError) as error:parser.exit(1,str(error)+'\n')
