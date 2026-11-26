#!/usr/bin/env node
'use strict';
// Local-only validation: no GitHub Actions, Supabase cloud, or paid API.
// Default: all Node suites and syntax checks. --full: disposable local PostgreSQL + Chromium + Python.
const fs=require('node:fs'),path=require('node:path'),{spawnSync}=require('node:child_process'),{randomUUID}=require('node:crypto'),G=require('./local-v8-guard.cjs');
const root=path.resolve(__dirname,'..'),tools=path.join(root,'.v8-test-tools');
const sleep=ms=>Atomics.wait(new Int32Array(new SharedArrayBuffer(4)),0,0,ms);
function run(cmd,args,options={}){const q=spawnSync(cmd,args,{cwd:root,stdio:'inherit',...options});if(q.error||q.status!==0)throw Error(cmd+' '+args[0]+' failed: '+(q.error?.message||q.status));return q}
function npm(args){if(process.platform==='win32'){const cli=path.join(path.dirname(process.execPath),'node_modules','npm','bin','npm-cli.js');if(!fs.existsSync(cli))throw Error('Install Node.js LTS with npm (free).');return run(process.execPath,[cli,...args])}return run('npm',args)}
const scripts=folder=>fs.readdirSync(path.join(root,folder)).filter(n=>n.endsWith('.js')).map(n=>path.join(folder,n));
function units(){
 const suites=fs.readdirSync(path.join(root,'tests')).filter(n=>n.endsWith('.test.js')).map(n=>path.join('tests',n));
 for(const p of [...scripts('v2'),...scripts('v8'),'tests/v8-browser.cjs','scripts/test-v8-local.cjs','scripts/start-v8-local.cjs','scripts/local-v8-guard.cjs'])run(process.execPath,['--check',p]);
 run(process.execPath,['--test',...suites]);
 console.log('PASS Node unit suites and JS syntax');
}
function findBrowser(){
 const p=process.env.CHROME_BIN;
 if(p&&fs.existsSync(p))return p;
 const bases=[process.env.ProgramFiles,process.env['ProgramFiles(x86)'],process.env.LOCALAPPDATA].filter(Boolean);
 const candidates=process.platform==='win32'?bases.flatMap(b=>['Google/Chrome/Application/chrome.exe','Microsoft/Edge/Application/msedge.exe'].map(x=>path.join(b,x))):['/usr/bin/google-chrome','/usr/bin/chromium','/usr/bin/chromium-browser','/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'];
 const bin=candidates.find(x=>fs.existsSync(x));if(!bin)throw Error('Install free Chrome/Chromium/Edge or set CHROME_BIN to its executable.');return bin
}
function full(){
 const chrome=findBrowser();G.assertDockerLocal();run('docker',['info','--format','{{.ServerVersion}}']);
 fs.mkdirSync(tools,{recursive:true});npm(['install','--prefix',tools,'--no-audit','--no-fund','--ignore-scripts','--save-exact','playwright-core@1.65.1']);
 const python=process.platform==='win32'?'py':'python3',pyArgs=process.platform==='win32'?['-3']:[];
 const venv=path.join(tools,'legacy-venv');if(!fs.existsSync(venv))run(python,[...pyArgs,'-m','venv',venv]);
 const py=path.join(venv,process.platform==='win32'?'Scripts/python.exe':'bin/python');
 run(py,['-m','pip','install','-r','scripts/requirements-legacy.txt']);run(py,['tests/test_legacy_converter.py']);
 const name='staff-v8-ci-'+randomUUID().replace(/-/g,'').slice(0,16);let created=false;
 try{
  run('docker',['run','--rm','-d','--name',name,'--label','baanjergun.v8.test=synthetic','-e','POSTGRES_PASSWORD=synthetic-ci-password','-e','POSTGRES_DB=staff_ci','postgres:17']);created=true;
  let ready=false;for(let i=0;i<120;i++){const q=spawnSync('docker',['exec',name,'pg_isready','-h','127.0.0.1','-U','postgres','-d','staff_ci'],{stdio:'ignore'});if(q.status===0){ready=true;break}sleep(500)}
  if(!ready)throw Error('Disposable database did not start');
  const sql=file=>{run('docker',['exec','-i',name,'psql','-X','-v','ON_ERROR_STOP=1','-U','postgres','-d','staff_ci'],{input:fs.readFileSync(path.join(root,file)),stdio:['pipe','inherit','inherit']});console.log('PASS '+file)};
  sql('tests/ci_bootstrap.sql');
  for(const file of fs.readdirSync(path.join(root,'supabase/migrations')).filter(f=>f.endsWith('.sql')).sort())sql(path.join('supabase/migrations',file));
  sql('tests/ci_seed.sql');
  for(const file of fs.readdirSync(path.join(root,'supabase/tests')).filter(f=>f.endsWith('.sql')).sort())sql(path.join('supabase/tests',file));
  run(process.execPath,['tests/v8-browser.cjs'],{env:{...process.env,V8_DB_CONTAINER:name,V8_SKIP_POC:'1',V8_TOOLS:tools,NODE_PATH:path.join(tools,'node_modules'),CHROME_BIN:chrome}});
  console.log('PASS full local SQL and browser workflow; no cloud runner used.');
 }finally{if(created)spawnSync('docker',['rm','-f',name],{stdio:'inherit'})}
}
try{const flags=process.argv.slice(2);if(flags.some(x=>x!=='--full'))throw Error('Usage: node scripts/test-v8-local.cjs [--full]');units();if(flags.includes('--full'))full();else console.log('Unit only; --full also runs SQL, Python and Chromium on this machine.')}catch(e){console.error(e.message);process.exitCode=1}
