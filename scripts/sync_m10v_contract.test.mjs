import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,readFile,writeFile,rm} from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {syncContract} from './sync_m10v_contract.mjs';
const sourceDir='/Users/zhaoo/.codex/worktrees/film-companion/m10v';
test('generated catalog keeps stable film identity and detects snapshot corruption',async()=>{
 const outputDir=await mkdtemp(path.join(os.tmpdir(),'gremote-catalog-'));
 try{
  const manifest=await syncContract({sourceDir,outputDir});
  const catalog=JSON.parse(await readFile(path.join(outputDir,'assets/films/catalog.json')));
  assert.equal(catalog.entries.length,47);assert.ok(catalog.entries.some(f=>f.id===289));
  assert.equal(new Set(catalog.entries.map(f=>f.id)).size,47);
  assert.match(manifest.rendererHash,/^[a-f0-9]{64}$/);
  assert.equal(catalog.entries.find(f=>f.id===67).parameters.filmExposure.max,1);
  assert.equal(catalog.entries.find(f=>f.id===75).parameters.haloGain,undefined);
  await syncContract({sourceDir,outputDir,check:true});
  await writeFile(path.join(outputDir,'assets/films/catalog.json'),'{}');
  await assert.rejects(syncContract({sourceDir,outputDir,check:true}),/snapshot mismatch/);
 }finally{await rm(outputDir,{recursive:true,force:true});}
});
