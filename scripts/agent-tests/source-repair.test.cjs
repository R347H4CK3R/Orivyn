const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path'),{spawnSync}=require('node:child_process');
let api;try{api=require('../../JarvisEVO/Resources/SourceRepairDraft.js')}catch{}
const base={path:'Sources/Main.swift',commitSHA:'a'.repeat(40),blobSHA:'b'.repeat(40),originalText:'let x = 1\n',replacementText:'let x = 2\n',summary:'Change the local value'};
const draft=(changes={})=>{assert.ok(api,'Source repair draft module missing');return JSON.parse(api.create(JSON.stringify({...base,...changes})));};
function apply(originalText,replacementText){const d=draft({originalText,replacementText});const dir=fs.mkdtempSync(path.join(os.tmpdir(),'orivyn-draft-'));try{fs.mkdirSync(path.join(dir,'Sources'));fs.writeFileSync(path.join(dir,base.path),originalText);const r=spawnSync('patch',['--batch','--fuzz=0','-p1'],{cwd:dir,input:d.diff,encoding:'utf8'});assert.equal(r.error,undefined);assert.equal(r.status,0,r.stdout+r.stderr);assert.equal(fs.readFileSync(path.join(dir,base.path),'utf8'),replacementText);return d;}finally{fs.rmSync(dir,{recursive:true,force:true});}}
test('draft is explicitly unapplied and makes no cryptographic verification claim',()=>{const d=draft();assert.equal(d.status,'draftNotApplied');assert.equal(d.path,base.path);assert.equal(d.commitSHA,base.commitSHA);assert.equal(d.blobSHA,base.blobSHA);assert.ok(d.limitations.some(x=>/SHA|hash|integrity/i.test(x)));assert.ok(d.limitations.some(x=>/not.*(applied|executed)|no.*(write|execution)/i.test(x)));assert.equal(typeof d.diff,'string');});
test('single hunk applies a localized change with context',()=>{const d=apply('a\nb\nc\nd\ne\nf\ng\nh\ni\n','a\nb\nc\nd\nNEW\nf\ng\nh\ni\n');assert.equal((d.diff.match(/^@@/gm)||[]).length,1);});
test('empty files and whole-file additions/deletions apply exactly',()=>{apply('','a\n');apply('a\n','');apply('','a');apply('a','');});
test('no-final-newline markers preserve both directions and replacement',()=>{for(const [a,b] of [['x','x\n'],['x\n','x'],['x','y'],['a\nb','a\nc\n'],['a\nb\n','a\nc']])apply(a,b);assert.match(draft({originalText:'x',replacementText:'y'}).diff,/\\ No newline at end of file/);});
test('CRLF and blank lines retain exact bytes',()=>{apply('a\r\nb\r\n','a\r\nc\r\n');apply('\n\na\n\n','\n\nb\n\n');apply('a\r\nb','a\r\nc\r\n');});
test('unicode and inert shell/script-looking source remain data',()=>{apply('let a = "😀"\n','let a = "é🚀"\n');const d=apply('x\n','$(touch pwned)\n<script>globalThis.pwned=true</script>\n');assert.equal(globalThis.pwned,undefined);assert.match(d.diff,/touch pwned/);});
test('rejects path injection, unsupported files, invalid SHAs and schema extras',()=>{for(const p of ['../a.swift','/a.swift','a/../b.swift','a//b.swift','a\\b.swift','a\tb.swift','a b.swift','.git/config.swift','.GIT/config.swift','secret.env','a.swift\n+++ hacked'])assert.throws(()=>draft({path:p}),p);for(const sha of ['a'.repeat(39),'z'.repeat(40)])assert.throws(()=>draft({blobSHA:sha}));assert.throws(()=>draft({extra:true}));});
test('rejects duplicate keys, invalid Unicode, controls and unchanged text',()=>{assert.ok(api);const json=JSON.stringify(base);assert.throws(()=>api.create(json.replace('"path":','"path":"other.swift","path":')));assert.throws(()=>draft({originalText:'\ud800'}));assert.throws(()=>draft({replacementText:'\u0000'}));assert.throws(()=>draft({replacementText:'\u0085'}));assert.throws(()=>draft({summary:'line\nline'}));assert.throws(()=>draft({replacementText:base.originalText}));});
test('enforces UTF8 text/summary and diff-output bounds',()=>{assert.throws(()=>draft({originalText:'😀'.repeat(32769)}));assert.throws(()=>draft({summary:'é'.repeat(251)}));assert.throws(()=>draft({originalText:'\n'.repeat(131072),replacementText:'x\n'.repeat(65536)}));});
test('handles bounded long lines linearly without splitting content',()=>{apply('a'.repeat(120000),'b'.repeat(120000));});

function applyExport(originalText,replacementText){
 const d=draft({originalText,replacementText});
 assert.equal(typeof d.patch,'string','exported patch bytes must exist');
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'orivyn-export-'));
 try{
  fs.mkdirSync(path.join(dir,'Sources'));fs.writeFileSync(path.join(dir,base.path),originalText);
  for(const args of [['apply','--check','--whitespace=nowarn','-'],['apply','--whitespace=nowarn','-']]){
   const r=spawnSync('git',args,{cwd:dir,input:d.patch,encoding:'utf8'});
   assert.equal(r.error,undefined);assert.equal(r.status,0,r.stdout+r.stderr);
  }
  assert.deepEqual(fs.readFileSync(path.join(dir,base.path)),Buffer.from(replacementText));
  return d;
 }finally{fs.rmSync(dir,{recursive:true,force:true});}
}
test('export includes pinned identity and explicit unapplied status without changing diff bytes',()=>{
 const d=applyExport(base.originalText,base.replacementText);
 assert.ok(d.patch.startsWith('# Orivyn proposed source change\n'));
 for(const s of [base.path,base.commitSHA,base.blobSHA,base.summary,'not applied or tested','Recheck the base commit and blob before applying'])assert.ok(d.patch.includes(s),s);
 assert.ok(d.patch.endsWith(d.diff));assert.match(d.exportFilename,/^Orivyn-[A-Za-z0-9._-]+\.patch$/);
});
test('export is applicable with Git and retains unicode, CRLF, no-final-newline and empty contents',()=>{
 for(const [a,b] of [['','new\n'],['old\n',''],['x','y'],['x','x\n'],['x\n','x'],['a\r\nb\r\n','a\r\nc\r\n'],['let a = "😀"\n','let a = "é🚀"\n']])applyExport(a,b);
});
test('export rejects changed hunk without overwriting the current file',()=>{
 const d=draft(),dir=fs.mkdtempSync(path.join(os.tmpdir(),'orivyn-stale-export-'));
 try{
  assert.equal(typeof d.patch,'string');fs.mkdirSync(path.join(dir,'Sources'));
  const current='let x = 999\n';fs.writeFileSync(path.join(dir,base.path),current);
  const r=spawnSync('git',['apply','--check','-'],{cwd:dir,input:d.patch,encoding:'utf8'});
  assert.equal(r.error,undefined);assert.notEqual(r.status,0);
  assert.equal(fs.readFileSync(path.join(dir,base.path),'utf8'),current);
 }finally{fs.rmSync(dir,{recursive:true,force:true});}
});
test('export filename is flat and bounded even for long nested paths',()=>{
 const d=draft({path:'nested/'+ 'a'.repeat(900)+'.swift'});
 assert.equal(typeof d.exportFilename,'string');assert.ok(Buffer.byteLength(d.exportFilename)<=120);
 assert.ok(!/[\\/]/.test(d.exportFilename));assert.ok(d.exportFilename.endsWith('.patch'));
 assert.ok(Buffer.byteLength(d.patch)<=310000);
});
test('patch header is inert even when summary resembles commands or patch syntax',()=>{
 const summary='$(touch SHOULD_NOT_EXIST) --- a/other.swift +++ b/other.swift';
 const d=draft({summary});assert.equal(typeof d.patch,'string');assert.ok(d.patch.includes('# Summary: '+summary+'\n'));
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'orivyn-header-'));
 try{
  fs.mkdirSync(path.join(dir,'Sources'));fs.writeFileSync(path.join(dir,base.path),base.originalText);
  const r=spawnSync('git',['apply','-'],{cwd:dir,input:d.patch,encoding:'utf8'});
  assert.equal(r.status,0,r.stderr);assert.equal(fs.existsSync(path.join(dir,'SHOULD_NOT_EXIST')),false);
  assert.equal(fs.readFileSync(path.join(dir,base.path),'utf8'),base.replacementText);
 }finally{fs.rmSync(dir,{recursive:true,force:true});}
});
test('export retains real Git base identities and applies after explicit base verification',()=>{
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'orivyn-pinned-export-'));
 function git(args,input){const r=spawnSync('git',args,{cwd:dir,input,encoding:'utf8'});assert.equal(r.error,undefined);assert.equal(r.status,0,r.stdout+r.stderr);return r.stdout.trim();}
 try{
  git(['init','-q']);fs.mkdirSync(path.join(dir,'Sources'));fs.writeFileSync(path.join(dir,base.path),base.originalText);
  git(['add','Sources/Main.swift']);git(['-c','user.name=Local Test','-c','user.email=test@local.invalid','-c','commit.gpgsign=false','commit','-qm','Fixture baseline']);
  const commitSHA=git(['rev-parse','HEAD']),blobSHA=git(['rev-parse','HEAD:'+base.path]);
  const d=draft({commitSHA,blobSHA});
  assert.ok(d.patch.includes('# Base commit: '+commitSHA+'\n'));assert.ok(d.patch.includes('# Base blob: '+blobSHA+'\n'));
  // The consumer explicitly checks identities; patch comments alone do not enforce them.
  assert.equal(git(['rev-parse','HEAD']),commitSHA);assert.equal(git(['hash-object',base.path]),blobSHA);
  git(['apply','--check','-'],d.patch);git(['apply','-'],d.patch);
  assert.equal(fs.readFileSync(path.join(dir,base.path),'utf8'),base.replacementText);
 }finally{fs.rmSync(dir,{recursive:true,force:true});}
});
