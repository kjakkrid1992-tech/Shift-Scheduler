#!/usr/bin/env node
'use strict';
// One-machine, local-only runtime. No login to Supabase cloud, project creation, reset or linking.
// Requires Node.js LTS, local Docker-compatible runtime and standalone Supabase CLI.
const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),{spawnSync}=require('node:child_process'),{randomBytes}=require('node:crypto'),R=require('../v8/runtime-config.js');
const root=path.resolve(__dirname,'..'),work=path.join(root,'local-v8-runtime'),tools=path.join(root,'.v8-test-tools'),publicDir=path.join(root,'v8');
function run(cmd,args,{cwd=work,capture=false}={}){const q=spawnSync(cmd,args,{cwd,encoding:'utf8',maxBuffer:8*1024*1024,stdio:capture?['ignore','pipe','pipe']:'inherit'});if(q.error||q.status!==0)throw Error(cmd+' '+args[0]+' failed. Check local prerequisites and CLI output. '+(q.error?.message||''));return capture?q.stdout:''}
function cli(args,capture=false){return run('supabase',args,{capture})}
function npm(args){if(process.platform==='win32'){const p=path.join(path.dirname(process.execPath),'node_modules','npm','bin','npm-cli.js');if(!fs.existsSync(p))throw Error('Node.js with npm is required.');return run(process.execPath,[p,...args],{cwd:root})}return run('npm',args,{cwd:root})}
function localWork(){
 fs.mkdirSync(work,{recursive:true});
 if(fs.lstatSync(work).isSymbolicLink())throw Error('Local runtime must not be a symlink');
 const dir=path.join(work,'supabase');
 if(fs.existsSync(path.join(dir,'.temp','project-ref'))||fs.existsSync(path.join(dir,'.branches')))throw Error('Linked or branch directory detected. Refusing to touch it.');
 let cfg=['config.toml','config.jsonc'].map(x=>path.join(dir,x)).find(x=>fs.existsSync(x));
 if(!cfg){cli(['init']);cfg=['config.toml','config.jsonc'].map(x=>path.join(dir,x)).find(x=>fs.existsSync(x))}
 if(!cfg)throw Error('Supabase CLI did not generate local config');
 const conf=fs.readFileSync(cfg,'utf8'),signup=/(enable_signup\s*=\s*|\"enable_signup\"\s*:\s*)(true|false)/g;
 if(!signup.test(conf))throw Error('Cannot verify local signup setting; disable signup in local config before using this script.');
 signup.lastIndex=0;const locked=conf.replace(signup,(_,prefix)=>prefix+'false');if(locked!==conf)fs.writeFileSync(cfg,locked,'utf8');
 const target=path.join(dir,'migrations');fs.mkdirSync(target,{recursive:true});
 const source=path.join(root,'supabase','migrations');
 for(const n of fs.readdirSync(source).filter(n=>n.endsWith('.sql')).sort()){const from=path.join(source,n),to=path.join(target,n);if(fs.existsSync(to)&&!fs.readFileSync(to).equals(fs.readFileSync(from)))throw Error('Existing local migration differs: '+n+' — no reset performed');if(!fs.existsSync(to))fs.copyFileSync(from,to)}
}
function validateStatus(status){
 const c=R.normalizeConfig({url:status.API_URL,publishableKey:status.ANON_KEY||status.PUBLISHABLE_KEY});
 if(!c.local)throw Error('Refusing non-loopback API endpoint');
 if(typeof status.SERVICE_ROLE_KEY!=='string'||status.SERVICE_ROLE_KEY.split('.').length!==3)throw Error('Local legacy service-role key not available; use local Studio to create Auth users. No hosted request sent.');
 const part=JSON.parse(Buffer.from(status.SERVICE_ROLE_KEY.split('.')[1],'base64url').toString('utf8'));if(part.role!=='service_role')throw Error('Local admin key has wrong role');
 return c;
}
async function admin(c,key,endpoint,method='GET',body){
 if(!endpoint.startsWith('/auth/v1/admin/users'))throw Error('Unexpected local admin route');
 const q=await fetch(c.url+endpoint,{method,redirect:'error',headers:{apikey:key,Authorization:'Bearer '+key,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});
 if(!q.ok)throw Error('Local Auth admin request failed: HTTP '+q.status);
 return q.json();
}
function localQuery(sql){const help=cli(['db','query','--help'],true);if(!help.includes('--local'))throw Error('This script requires a CLI version with explicit --local db query; no remote SQL run.');cli(['db','query',sql,'--local'])}
async function users(c,status){
 const data=await admin(c,status.SERVICE_ROLE_KEY,'/auth/v1/admin/users?page=1&per_page=1000');
 if(!Array.isArray(data.users)||data.users.length>=1000)throw Error('Unexpected local auth user list');
 for(const role of ['owner','manager']){
  const email=role+'-v8@example.com';let u=data.users.find(x=>x.email===email),password;
  if(!u){password=randomBytes(18).toString('base64url')+'Aa1!';const created=await admin(c,status.SERVICE_ROLE_KEY,'/auth/v1/admin/users','POST',{email,password,email_confirm:true});u=created.user||created;console.log('New local '+role+': '+email+' / '+password+' (save locally; never commit)')}
  else console.log('Existing local '+role+': '+email+' (password unchanged)');
  if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(u.id))throw Error('Invalid local Auth user ID');
  localQuery("do $$ begin insert into public.user_profiles(user_id,display_name,role) values('"+u.id+"','Local "+role+"','"+role+"') on conflict(user_id) do nothing; if not exists(select 1 from public.user_profiles where user_id='"+u.id+"' and role='"+role+"' and active) then raise exception 'Existing profile mismatch';end if;end $$;");
 }
}
function serve(config,sdk){
 const bodyConfig='window.STAFF_CONFIG='+JSON.stringify({...config,localOnly:true})+';\n';
 const server=http.createServer((req,res)=>{try{
  if(req.method!=='GET'&&req.method!=='HEAD'){res.writeHead(405);res.end();return}
  const u=new URL(req.url,'http://127.0.0.1:5501'),p=u.pathname;
  const reply=(type,b)=>{res.setHeader('Content-Type',type);res.setHeader('Cache-Control','no-store');res.setHeader('X-Content-Type-Options','nosniff');res.end(req.method==='HEAD'?undefined:b)};
  if(p==='/'||p==='/v8'){res.writeHead(302,{Location:'/v8/'});res.end();return}
  if(p==='/v8/config.js'){reply('application/javascript; charset=utf-8',bodyConfig);return}
  if(p==='/v8/sdk.js'){reply('application/javascript; charset=utf-8',fs.readFileSync(sdk));return}
  if(p==='/v8/'||p==='/v8/index.html'){reply('text/html; charset=utf-8',fs.readFileSync(path.join(publicDir,'index.html'),'utf8').replace('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.49.4/dist/umd/supabase.js','./sdk.js'));return}
  if(!/^\/v8\/[a-z0-9-]+\.(?:js|css)$/i.test(p)){res.writeHead(404);res.end();return}
  const file=path.join(publicDir,path.basename(p));if(!fs.existsSync(file)){res.writeHead(404);res.end();return}reply(p.endsWith('.css')?'text/css; charset=utf-8':'application/javascript; charset=utf-8',fs.readFileSync(file))
 }catch{res.writeHead(500);res.end('Local server error')}});server.on('error',e=>{console.error('Local port 5501 unavailable: '+e.message);process.exitCode=1});server.listen(5501,'127.0.0.1',()=>console.log('V8 LOCAL: http://127.0.0.1:5501/v8/ — Ctrl+C stops only the web server.'));
}
async function main(){
 if(process.argv.length!==2)throw Error('Usage: node scripts/start-v8-local.cjs');
 run('docker',['info','--format','{{.ServerVersion}}'],{cwd:root});run('supabase',['--version'],{cwd:root});
 localWork();console.log('Starting local Supabase stack (no cloud project).');cli(['start'],true);
 const status=JSON.parse(cli(['status','-o','json'],true)),config=validateStatus(status);
 // Check migration before creating accounts. No reset or cloud link.
 localQuery("do $$ begin if to_regprocedure('public.v8_workspace_capabilities()') is null or to_regprocedure('public.save_attendance_period(date,uuid,text,jsonb)') is null or to_regprocedure('public.save_payroll_period_drafts(date,jsonb)') is null then raise exception 'V8 migration missing in local runtime';end if;end $$;");
 fs.mkdirSync(tools,{recursive:true});const sdk=path.join(tools,'node_modules','@supabase','supabase-js','dist','umd','supabase.js');
 if(!fs.existsSync(sdk))npm(['install','--prefix',tools,'--no-audit','--no-fund','--ignore-scripts','--save-exact','@supabase/supabase-js@2.49.4']);
 if(!fs.existsSync(sdk))throw Error('Local Supabase SDK unavailable');
 await users(config,status);serve(config,sdk);
}
main().catch(e=>{console.error(e.message);process.exitCode=1});
