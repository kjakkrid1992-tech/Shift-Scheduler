/* Real Chromium + real disposable PostgreSQL business RPCs. Test-only transport; not Supabase Auth/PostgREST. */
'use strict';
const assert=require('node:assert/strict'),http=require('node:http'),fs=require('node:fs'),path=require('node:path'),{execFileSync}=require('node:child_process'),{chromium}=require('playwright-core');
const root=path.resolve(__dirname,'..'),owner='00000000-0000-4000-8000-000000000001',manager='00000000-0000-4000-8000-000000000002';
const lit=v=>v===null||v===undefined?'null':"'"+String(v).replaceAll("'","''")+"'",j=v=>lit(JSON.stringify(v))+'::jsonb';
function psql(sql){return execFileSync(process.env.V8_DB_CONTAINER?'docker':'psql',[...(process.env.V8_DB_CONTAINER?['exec','-i',process.env.V8_DB_CONTAINER,'psql','-U','postgres','-d','staff_ci']:[]),'-X','-A','-t','-q','-v','ON_ERROR_STOP=1'],{input:sql+'\n',encoding:'utf8',maxBuffer:8*1024*1024,stdio:['pipe','pipe','pipe']}).trim()}
function asRole(role,query,write=false){const uid=role==='owner'?owner:manager;const out=psql("begin; set local role authenticated; select set_config('request.jwt.claim.sub',"+lit(uid)+",true); "+query+"; "+(write?'commit':'rollback')+";");return JSON.parse(out.split('\n').at(-1))}
const fixture="begin; set local role authenticated; select set_config('request.jwt.claim.sub',"+lit(owner)+",true); do $$ declare e uuid;j uuid;d uuid;i integer;begin select id into d from public.departments where name='หน้าร้าน';for i in 1..5 loop e:=public.create_staff('EMP-V8-BROWSER-'||i,'Synthetic','Browser-'||i,'','',d,'Test',case when i<=3 then 'daily' else 'monthly' end,'2008-01-26','active');select id into j from public.employment_records where employee_id=e;insert into public.compensation_history(employment_id,pay_type,base_rate,ot_rate,effective_from) values(j,case when i<=3 then 'daily' else 'monthly' end,case when i<=3 then 330 else 10000 end,50,'2008-01-26');end loop;end $$; commit;";
const tables=new Set(['employment_records','pay_periods','shift_schedules','shift_assignments','attendance_records','payroll_closures','payroll_drafts','payroll_final']);
const cols=new Set(['id','department_id','start_date','end_date','period_id','status','version','schedule_id','work_date','employment_id','period_start']);
function query(q){
 if(!tables.has(q.table))throw Error('Unexpected table '+q.table);
 const wh=[];for(const [op,k,v] of q.filters){if(op==='or'){if(!/^end_date\.is\.null,end_date\.gte\.\d{4}-\d{2}-\d{2}$/.test(k))throw Error('Unexpected OR');wh.push('(a.end_date is null or a.end_date >= '+lit(k.slice(-10))+')');continue}if(!cols.has(k)||!['eq','lte','gte'].includes(op))throw Error('Unexpected filter');wh.push('a.'+k+({eq:'=',lte:'<=',gte:'>='}[op])+lit(v))}
 const sel=q.table==='employment_records'?"a.*, (select jsonb_build_object('employee_code',e.employee_code,'first_name',e.first_name,'last_name',e.last_name,'nickname',e.nickname) from public.employees e where e.id=a.employee_id) as employees":"a.*";
 let sql='select coalesce(jsonb_agg(to_jsonb(t)),\'[]\'::jsonb) from (select '+sel+' from public.'+q.table+' a'+(wh.length?' where '+wh.join(' and '):'');
 if(q.order){if(!cols.has(q.order[0]))throw Error('Unexpected order');sql+=' order by a.'+q.order[0]+(q.order[1]?' asc':' desc')}
 if(q.limit){if(!Number.isInteger(q.limit)||q.limit<1||q.limit>1000)throw Error('Invalid limit');sql+=' limit '+q.limit}sql+=') t';
 const rows=asRole(q.role,sql);if(q.single){if(rows.length>1)throw Error('Multiple rows');return rows[0]||null}return rows
}
const rpcMap={
 save_attendance_period:[['p_month','date'],['p_department','uuid'],['p_mode','text'],['p_rows','jsonb']],
 preview_payroll:[['p_employment','uuid'],['p_month','date']],
 save_payroll_period_drafts:[['p_month','date'],['p_rows','jsonb']],
 close_payroll:[['p_month','date'],['p_reviews','jsonb'],['p_note','text']],
 record_payroll_payment:[['p_id','uuid'],['p_date','date'],['p_method','text'],['p_reference','text']],
 v8_workspace_capabilities:[]
};
let calls=[];
function rpc(q){if(!Object.hasOwn(rpcMap,q.name))throw Error('Unexpected RPC '+q.name);const args=rpcMap[q.name].map(([k,t])=>t==='jsonb'?j(q.args[k]):lit(q.args[k])+'::'+t);calls.push({name:q.name,role:q.role,count:q.args.p_rows?.length});return asRole(q.role,'select to_jsonb(public.'+q.name+'('+args.join(',')+'))',q.name!=='preview_payroll'&&q.name!=='v8_workspace_capabilities')}
function startServer(){return new Promise(resolve=>{
 const server=http.createServer(async(req,res)=>{try{if(req.url==='/test-api'&&req.method==='POST'){let body='';for await(const x of req){body+=x;if(body.length>5e6)throw Error('Test request too large')}const q=JSON.parse(body);if(!['owner','manager'].includes(q.role))throw Error('Test role');let result;try{result={data:q.name?rpc(q):query(q),error:null}}catch(e){result={data:null,error:{message:String(e.stderr||e.message).trim()}}}res.setHeader('Content-Type','application/json');res.end(JSON.stringify(result));return}
 const clean=new URL(req.url,'http://localhost').pathname;if(!clean.startsWith('/v8/')){res.writeHead(404);res.end();return}const p=path.resolve(root,'.'+(clean==='/v8/'?'/v8/index.html':clean));if(!p.startsWith(path.join(root,'v8')+path.sep)){res.writeHead(403);res.end();return}const ext=path.extname(p);res.setHeader('Content-Type',({'.html':'text/html; charset=utf-8','.js':'application/javascript; charset=utf-8','.css':'text/css; charset=utf-8'})[ext]||'application/octet-stream');res.end(fs.readFileSync(p))
 }catch(e){res.writeHead(500);res.end(String(e.message))}});server.listen(0,'127.0.0.1',()=>resolve(server))
 })}
function clientFactory(role){
 const send=async q=>{if(window.__failNext&&q.name===window.__failNext){window.__failNext='';return {error:{message:'Synthetic network failure'},data:null}}const r=await fetch('/test-api',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({...q,role})});return r.json()};
 return {from(table){const state={table,filters:[]},q={select(){return q},eq(k,v){state.filters.push(['eq',k,v]);return q},lte(k,v){state.filters.push(['lte',k,v]);return q},gte(k,v){state.filters.push(['gte',k,v]);return q},or(v){state.filters.push(['or',v]);return q},order(k,o={}){state.order=[k,o.ascending!==false];return q},limit(n){state.limit=n;return q},maybeSingle(){state.single=true;return send(state)},then(a,b){return send(state).then(a,b)}};return q},rpc(name,args={}){return send({name,args})}}
}
async function until(page,fn,arg){await page.waitForFunction(fn,arg,{timeout:20000})}
async function paste(page,selector,text){await page.locator(selector).evaluate((el,text)=>{const dt=new DataTransfer();dt.setData('text/plain',text);el.dispatchEvent(new ClipboardEvent('paste',{clipboardData:dt,bubbles:true,cancelable:true}))},text)}
async function main(){
 psql(fixture);
 const dept=asRole('owner',"select jsonb_build_object('id',id,'name',name,'active',active) from public.departments where name='หน้าร้าน'");
 const server=await startServer();let browser;
 try{
  browser=await chromium.launch({executablePath:process.env.CHROME_BIN,headless:true,args:['--no-sandbox']});
  const page=await browser.newPage({viewport:{width:1440,height:900}}),errors=[];
  page.on('pageerror',e=>errors.push(e.message));page.on('dialog',d=>d.accept());
  await page.route('https://cdn.jsdelivr.net/**',r=>r.fulfill({contentType:'application/javascript',body:'window.supabase={};'}));
  await page.goto('http://127.0.0.1:'+server.address().port+'/v8/');
  await page.evaluate(({factory,dept})=>{window.makeTestClient=Function('return ('+factory+')')();window.testDept=dept;document.getElementById('setup').hidden=true;document.getElementById('workspace').hidden=false;document.getElementById('employeeView').hidden=true;document.getElementById('attendanceView').hidden=false;window.AttendancePeriodPage.open(window.makeTestClient('manager'),'manager',[dept]);}, {factory:clientFactory.toString(),dept});
  await page.locator('#amMonth').fill('02/2008');await page.locator('#amLoad').click();await until(page,()=>document.querySelectorAll('#amRows tr').length===31);
  let row=page.locator('#amRows tr').first();assert.equal(await row.locator('[data-field=start]').isEnabled(),true);
  await paste(page,'#amRows tr:first-child [data-field=start]','06:30\t21:00\t0\t120\t480\tSynthetic paper card\n06:30\t15:30\t0\t60\t480\tSynthetic paper card');
  assert.equal(await row.locator('[data-field=start]').inputValue(),'06:30');assert.equal(await row.locator('[data-field=normalM]').inputValue(),'480');assert.match(await page.locator('#amTotals').innerText(),/4 ชม. 30 นาที/);
  await page.locator('#amUndo').click();assert.equal(await row.locator('[data-field=start]').inputValue(),'');
  await paste(page,'#amRows tr:first-child [data-field=start]','25:00\n06:30');assert.equal(await row.locator('[data-field=start]').inputValue(),'');
  await page.locator('#amEmployee').selectOption('*');await until(page,()=>document.querySelectorAll('#amRows tr').length===155);
  for(let i=0;i<5;i++){const idx=i*31+1;await paste(page,'#amRows tr:nth-child('+idx+') [data-field=start]','06:30\t21:00\t0\t120\t480\tSynthetic paper card\n06:30\t15:30\t0\t60\t480\tSynthetic paper card')}
  await page.locator('#amRows tr:first-child [data-field=start]').focus();await page.keyboard.press('Enter');assert.equal(await page.evaluate(()=>document.activeElement.closest('tr').rowIndex),2);
  await page.locator('#amSelectBlank').click();await page.locator('#amPreset').selectOption('off');await page.locator('#amApply').click();await page.locator('#amSelectDirty').click();
  await page.evaluate(()=>window.__failNext='save_attendance_period');await page.locator('#amVerify').click();await until(page,()=>document.getElementById('amMessage').textContent.includes('Synthetic network failure'));assert.match(await page.locator('#amSelected').innerText(),/155/);
  await page.locator('#amVerify').click();await until(page,()=>document.getElementById('amMessage').textContent.includes('สำเร็จ 155 วัน'));
  assert.equal(await page.locator('#amRows tr:first-child [data-field=start]').isDisabled(),true);
  await page.evaluate(()=>{window.AttendancePeriodPage.open(window.makeTestClient('owner'),'owner',[window.testDept])});await page.locator('#amMonth').fill('02/2008');await page.locator('#amLoad').click();await until(page,()=>document.querySelectorAll('#amRows tr').length===31);await page.locator('#amEmployee').selectOption('*');await page.locator('#amSelectVerified').click();await page.locator('#amApprove').click();await until(page,()=>document.getElementById('amMessage').textContent.includes('สำเร็จ 155 วัน'));
  assert.equal(asRole('owner',"select to_jsonb(count(*)) from public.attendance_records where work_date between '2008-01-26' and '2008-02-25' and status='approved' and schedule_id is null"),155);
  await page.evaluate(()=>{window.AttendancePeriodPage.reset();window.PayrollPage.open(window.makeTestClient('manager'),'manager')});await page.locator('#prOverview').waitFor({state:'visible'});await page.locator('#prMonth').fill('02/2008');await page.locator('#prRoster').click();await until(page,()=>document.querySelectorAll('#prOverviewRows tr').length===5);
  await page.locator('#prMatrix summary').click();await page.locator('#prMatrixLoad').click();await until(page,()=>document.querySelectorAll('#prMatrixRows tr').length===5);
  await page.locator('#prMatrixSelect').click();await page.locator('#prMatrixZero').click();
  for(let i=4;i<=5;i++)await page.locator('#prMatrixRows input[aria-label="ค่าแรง/เงินเดือน EMP-V8-BROWSER-'+i+'"]').fill('10000');
  await page.locator('#prMatrixNote').fill('Synthetic reviewed totals');await page.locator('#prMatrixApplyNote').click();
  await page.locator('#prMatrixRows tr:first-child input[type=checkbox]').uncheck();await page.locator('#prMatrixSave').click();await until(page,()=>document.getElementById('prMessage').textContent.includes('ไม่ได้เลือก'));await page.locator('#prMatrixRows tr:first-child input[type=checkbox]').check();
  await page.locator('#prMatrixSave').click();await until(page,()=>document.getElementById('prMessage').textContent.includes('บันทึกฉบับร่างพร้อมกัน 5 คน'));
  assert.equal(asRole('owner',"select to_jsonb(sum(net_satang)) from public.payroll_drafts where period_start='2008-01-26'"),2310500);
  await page.evaluate(()=>{window.PayrollPage.reset();window.PayrollPage.open(window.makeTestClient('owner'),'owner')});await page.locator('#prOverview').waitFor({state:'visible'});await page.locator('#prMonth').fill('02/2008');await page.locator('#prRoster').click();await until(page,()=>!document.getElementById('prClose').disabled&&document.querySelectorAll('#prOverviewRows tr').length===5);
  await page.locator('#prCloseNote').fill('Synthetic full review');await page.locator('#prClose').click();await until(page,()=>document.getElementById('prOverviewStatus').textContent.includes('ปิดรอบแล้ว'));
  await page.evaluate(()=>window.print=()=>{window.__printed=document.querySelectorAll('#prSlip article').length});await page.locator('#prPrintAll').click();assert.equal(await page.evaluate(()=>window.__printed),5);
  const emp=await page.locator('#prEmployee option').first().getAttribute('value');await page.locator('#prEmployee').selectOption(emp);await page.locator('#prLoad').click();await page.locator('#prRecordPay').waitFor({state:'visible'});await page.locator('#prRecordPay').click();await page.locator('#prPaymentForm input[name=date]').fill('26/02/2008');await page.locator('#prPaymentForm select[name=method]').selectOption('cash');await page.locator('#prPaymentForm button[type=submit]').click();await until(page,()=>document.getElementById('prFinalStatus').textContent.includes('บันทึกจ่ายแล้ว'));
  assert.equal(asRole('owner',"select to_jsonb(sum(net_satang)) from public.payroll_final where period_start='2008-01-26'"),2310500);
  assert.equal(asRole('owner',"select to_jsonb(count(*)) from public.payroll_final where period_start='2008-01-26' and paid_at is not null"),1);
  assert.deepEqual(errors,[]);console.log('PASS Chromium V8: 155 attendance rows, atomic verify/approve, five payroll drafts, final close, print five slips, payment, real isolated PostgreSQL');
  console.log('Browser RPC batches:',JSON.stringify(calls.filter(c=>c.count)));
  if(process.env.V8_SKIP_POC==='1')return;
  // Separate synthetic Tabulator POC; no production dependencies or real data.
  const poc=await browser.newPage();await poc.setContent('<div id="grid"></div>');await poc.addStyleTag({path:path.join(process.env.V8_TOOLS,'node_modules/tabulator-tables/dist/css/tabulator.min.css')});await poc.addScriptTag({path:path.join(process.env.V8_TOOLS,'node_modules/tabulator-tables/dist/js/tabulator.min.js')});
  await poc.evaluate(()=>{window.grid=new Tabulator('#grid',{data:Array.from({length:155},(_,i)=>({id:i+1,name:'พนักงาน '+(Math.floor(i/31)+1),start:'06:30',locked:i===1})),index:'id',height:500,selectableRange:1,clipboard:true,clipboardCopyRowRange:'range',clipboardPasteParser:'range',clipboardPasteAction:'range',columns:[{title:'พนักงาน',field:'name'},{title:'เข้า',field:'start',editor:'input',editable:cell=>!cell.getRow().getData().locked}]});window.grid.on('tableBuilt',()=>window.__built=true)});
  await until(poc,()=>window.__built===true);
  await poc.evaluate(()=>window.grid.getRow(1).getCell('start').edit());const editor=poc.locator('#grid .tabulator-cell[tabulator-field=start] input');await editor.fill('07:00');await editor.press('Enter');
  assert.equal(await poc.evaluate(()=>window.grid.getData()[0].start),'07:00');assert.equal(await poc.evaluate(()=>window.grid.getData().length),155);
  console.log('PASS Tabulator synthetic POC: 155 Thai-labelled rows and inline editing; not adopted into live workspace until locked-range paste and workflow benchmark verified');
 }finally{if(browser)await browser.close();await new Promise(resolve=>server.close(resolve))}
}
main().catch(e=>{console.error(e);process.exitCode=1});
