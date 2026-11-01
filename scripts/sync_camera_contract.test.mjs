import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,mkdir,readFile,writeFile,rm} from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {copyCameraMetadata} from './sync_camera_contract.mjs';
const canonical=v=>Array.isArray(v)?'['+v.map(canonical).join(',')+']':v&&typeof v==='object'?'{'+Object.keys(v).sort().map(k=>JSON.stringify(k)+':'+canonical(v[k])).join(',')+'}':JSON.stringify(v);
test('camera metadata rebases identity without replacing local renderer or catalog',async()=>{
 const root=await mkdtemp(path.join(os.tmpdir(),'camera-metadata-'));
 try{
 const source=path.join(root,'source'),output=path.join(root,'output');
 for(const p of ['source/assets/films/icons','output/assets/films','output/lib/camera/companion','output/native/imaging/vendor'])await mkdir(path.join(root,p),{recursive:true});
 const catalog={hash:'old',rendererHash:'r'.repeat(64),entries:[{id:321,icon:'assets/films/icons/321.png'}]};
 await writeFile(path.join(source,'assets/films/catalog.json'),JSON.stringify(catalog));
 await writeFile(path.join(source,'assets/films/icons/321.png'),'fixture icon');
 await writeFile(path.join(source,'assets/films/companion-v1.json'),'{}');
 await writeFile(path.join(source,'assets/films/source-manifest.json'),'{}');
 for(const p of ['assets/films/catalog.json','native/imaging/vendor/renderer.c'])await writeFile(path.join(output,p),'old pinned bytes');
 const result=await copyCameraMetadata(source,output);
 const next=JSON.parse(await readFile(path.join(output,'assets/films/camera-catalog.json')));delete next.hash;
 assert.equal(result.catalogHash,createHash('sha256').update(canonical(next)).digest('hex'));
 assert.equal(next.entries[0].icon,'assets/films/camera-icons/321.png');
 assert.equal(await readFile(path.join(output,next.entries[0].icon),'utf8'),'fixture icon');
 for(const p of ['assets/films/catalog.json','native/imaging/vendor/renderer.c'])assert.equal(await readFile(path.join(output,p),'utf8'),'old pinned bytes');
 assert.match(await readFile(path.join(output,'lib/camera/companion/generated_camera_contract.dart'),'utf8'),new RegExp(result.catalogHash));
 }finally{await rm(root,{recursive:true,force:true});}
});
