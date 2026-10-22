import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {execFileSync,spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const project=fileURLToPath(new URL('../',import.meta.url));
function fixture(t){
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'rmd release-'));t.after(()=>fs.rmSync(root,{recursive:true,force:true}));
 const env={...process.env,GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_NOSYSTEM:'1',GIT_AUTHOR_DATE:'2020-01-01T00:00:00Z',GIT_COMMITTER_DATE:'2026-10-21T23:30:00Z',TZ:'Pacific/Honolulu'};
 const git=(...args)=>execFileSync('git',args,{cwd:root,env,encoding:'utf8',stdio:['ignore','pipe','pipe']}).trim();
 git('init','-q');fs.writeFileSync(path.join(root,'input'),'test\n');git('add','input');git('-c','user.name=Release Test','-c','user.email=test@example.invalid','commit','-qm','fixture');
 fs.mkdirSync(path.join(root,'scripts'));fs.copyFileSync(path.join(project,'scripts/release-tag.sh'),path.join(root,'scripts/release-tag.sh'));
 const sha=git('rev-parse','HEAD'),tag='261022-'+sha.slice(0,7);
 return {root,env,git,sha,tag};
}
function publication(t,{mode='missing',uploadFails=false,wrongSHA=false}={}){
 const f=fixture(t);const bin=path.join(f.root,'bin'),dist=path.join(f.root,'dist');fs.mkdirSync(bin);fs.mkdirSync(dist);
 for(const name of ['Rich Markdown Diff.app.zip','rich-markdown-diff-source.zip','SHA256SUMS'])fs.writeFileSync(path.join(dist,name),'fixture');
 const log=path.join(f.root,'calls.jsonl');
 fs.writeFileSync(path.join(bin,'gh'),`#!/usr/bin/env node
const fs=require('node:fs');const args=process.argv.slice(2);fs.appendFileSync(process.env.MOCK_LOG,JSON.stringify(args)+'\\n');
if(args[1]==='view'){
 if(process.env.MOCK_MODE==='missing')process.exit(1);
 const names=['Rich Markdown Diff.app.zip','rich-markdown-diff-source.zip','SHA256SUMS'];
 if(process.env.MOCK_MODE==='incomplete')names.pop();
 console.log(JSON.stringify({isDraft:process.env.MOCK_MODE==='draft',targetCommitish:process.env.MOCK_MODE==='wrong-target'?'wrong':process.env.GITHUB_SHA,assets:names.map(name=>({name}))}));
}else if(args[1]==='upload'&&process.env.FAIL_UPLOAD==='1')process.exit(1);
`);fs.chmodSync(path.join(bin,'gh'),0o755);
 const result=spawnSync('bash',[path.join(project,'scripts/publish-release.sh'),f.tag],{cwd:f.root,encoding:'utf8',env:{...f.env,PATH:bin+path.delimiter+process.env.PATH,MOCK_LOG:log,MOCK_MODE:mode,FAIL_UPLOAD:uploadFails?'1':'0',GH_TOKEN:'test-only',GITHUB_REPOSITORY:'example/repo',GITHUB_SHA:wrongSHA?'0'.repeat(40):f.sha,RUNNER_TEMP:f.root}});
 const calls=fs.existsSync(log)?fs.readFileSync(log,'utf8').trim().split('\n').filter(Boolean).map(s=>JSON.parse(s)):[];
 return {...f,result,calls};
}
test('release tag uses committer date in Seoul, not author date or local execution timezone',t=>{
 const f=fixture(t);const tag=execFileSync('bash',[path.join(project,'scripts/release-tag.sh')],{cwd:f.root,env:f.env,encoding:'utf8'}).trim();assert.equal(tag,f.tag);
 fs.writeFileSync(path.join(f.root,'input'),'uncommitted change');assert.equal(execFileSync('bash',[path.join(project,'scripts/release-tag.sh')],{cwd:f.root,env:{...f.env,TZ:'UTC'},encoding:'utf8'}).trim(),f.tag);
});
test('new release uploads every asset while draft and publishes last',t=>{
 const {result,calls,sha}=publication(t);assert.equal(result.status,0,result.stderr);assert.deepEqual(calls.map(c=>c[1]),['view','create','upload','edit']);assert.ok(calls[1].includes('--draft'));assert.equal(calls[1][calls[1].indexOf('--target')+1],sha);for(const asset of ['dist/Rich Markdown Diff.app.zip','dist/rich-markdown-diff-source.zip','dist/SHA256SUMS'])assert.ok(calls[2].includes(asset));assert.ok(calls[3].includes('--draft=false'));
});
test('rerun of a published release preserves existing immutable assets',t=>{
 const {result,calls}=publication(t,{mode:'published'});assert.equal(result.status,0,result.stderr);assert.deepEqual(calls.map(c=>c[1]),['view']);
});
test('rerun resumes an existing draft without creating another release',t=>{
 const {result,calls}=publication(t,{mode:'draft'});assert.equal(result.status,0,result.stderr);assert.deepEqual(calls.map(c=>c[1]),['view','upload','edit']);assert.ok(calls[1].includes('--clobber'));
});
test('upload failure leaves draft unpublished',t=>{
 const {result,calls}=publication(t,{uploadFails:true});assert.notEqual(result.status,0);assert.deepEqual(calls.map(c=>c[1]),['view','create','upload']);
});
test('published release targeting another commit is never overwritten',t=>{
 const {result,calls}=publication(t,{mode:'wrong-target'});assert.notEqual(result.status,0);assert.deepEqual(calls.map(c=>c[1]),['view']);
});
test('incomplete published release fails instead of reporting success',t=>{
 const {result,calls}=publication(t,{mode:'incomplete'});assert.notEqual(result.status,0);assert.deepEqual(calls.map(c=>c[1]),['view']);
});
test('mismatched checkout fails before contacting GitHub',t=>{
 const {result,calls}=publication(t,{wrongSHA:true});assert.notEqual(result.status,0);assert.equal(calls.length,0);
});
