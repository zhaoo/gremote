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
  assert.deepEqual(JSON.parse(await readFile(path.join(outputDir,'assets/films/source-manifest.json'))),manifest);
  assert.ok((await readFile(path.join(outputDir,'native/imaging/vendor/m10v/build_identity.h'),'utf8')).includes('GREMOTE_FILM_V1:'+manifest.rendererHash+':'+manifest.catalogHash+':'));
  assert.equal(catalog.entries.find(f=>f.id===67).parameters.filmExposure.max,1);
  assert.equal(catalog.entries.find(f=>f.id===75).parameters.haloGain,undefined);
  await syncContract({sourceDir,outputDir,check:true});
  await writeFile(path.join(outputDir,'assets/films/catalog.json'),'{}');
  await assert.rejects(syncContract({sourceDir,outputDir,check:true}),/snapshot mismatch/);
 }finally{await rm(outputDir,{recursive:true,force:true});}
});

test('repeat generation observes changed renderer and failed publication rolls back',async()=>{
 const {cp}=await import('node:fs/promises');
 const {execFileSync}=await import('node:child_process');
 const root=await mkdtemp(path.join(os.tmpdir(),'gremote-snapshot-change-'));
 const source=path.join(root,'source'),outputDir=path.join(root,'output');
 try {
  for(const name of ['native/gr3','node','web','vendor/darkslide','contracts','LICENSE','THIRD_PARTY_NOTICES.md'])
   await cp(path.join(sourceDir,name),path.join(source,name),{recursive:true});
  execFileSync('git',['init','-q',source]);
  execFileSync('git',['-C',source,'-c','user.name=Test','-c','user.email=test@invalid','commit','--allow-empty','-qm','fixture']);
  const iconCatalog=path.join(source,'web/gr3/film-icons/catalog.json');
  const icons=JSON.parse(await readFile(iconCatalog));
  const iconPath=icons.find(f=>f.id===33).icon_url;
  icons.forEach(f=>f.icon_url+='?v=fixture-version');
  await writeFile(iconCatalog,JSON.stringify(icons));
  const first=await syncContract({sourceDir:source,outputDir});
  assert.deepEqual(await readFile(path.join(outputDir,'assets/films/icons/33.png')),await readFile(path.join(source,'web'+iconPath)));
  const changed=path.join(source,'native/gr3/m10v_library.c');
  await writeFile(changed,(await readFile(changed))+'\n/* generation change */\n');
  const second=await syncContract({sourceDir:source,outputDir});
  assert.notEqual(first.rendererHash,second.rendererHash);
  assert.ok(second.files['node/gr3-sd-film-pack.mjs']);
  const before=await readFile(path.join(outputDir,'native/imaging/vendor/m10v/m10v_library.c'));
  await writeFile(changed,(await readFile(changed))+'\n/* interrupted publish */\n');
  let writes=0;
  await assert.rejects(syncContract({sourceDir:source,outputDir,publishFile:async(a,b)=>{
    if(++writes===4)throw Error('injected publication failure');
    const {rename}=await import('node:fs/promises');await rename(a,b);
  }}),/injected/);
  assert.deepEqual(await readFile(path.join(outputDir,'native/imaging/vendor/m10v/m10v_library.c')),before);
 }finally{await rm(root,{recursive:true,force:true});}
});
