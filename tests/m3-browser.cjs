/* Playwright smoke: real HTML and JS, mock Supabase, never writes production. */
const assert=require('node:assert/strict'),{chromium}=require('playwright'),http=require('node:http'),fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'..'),mock=fs.readFileSync(path.join(__dirname,'m3-browser-mock.js'),'utf8');
const server=http.createServer((req,res)=>{const p=path.resolve(root,'.'+new URL(req.url,'http://localhost').pathname);if(!p.startsWith(root+path.sep)){res.writeHead(403).end();return}const mime={'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8'};try{const b=fs.readFileSync(p);res.writeHead(200,{'content-type':mime[path.extname(p)]||'text/plain'});res.end(b)}catch{res.writeHead(404).end()}});
(async()=>{await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));const browser=await chromium.launch({headless:true});try{
 for(const role of ['manager','owner']){
 const page=await browser.newPage({viewport:{width:role==='manager'?1440:390,height:900}}),errors=[];page.on('pageerror',e=>errors.push(e.message));page.on('dialog',d=>d.accept());await page.clock.setFixedTime(new Date('2026-12-02T22:00:00+07:00'));
 await page.route('https://cdn.jsdelivr.net/**',route=>route.fulfill({contentType:'text/javascript',body:mock}));
 await page.route('**/v2/config.js',route=>route.fulfill({contentType:'text/javascript',body:'// mock config from SDK'}));
 await page.route('https://*.supabase.co/**',route=>route.abort());
 await page.goto('http://127.0.0.1:'+server.address().port+'/v2/index.html?role='+role);
 await page.locator('#workspace').waitFor({state:'visible'});await page.locator('#m3QuickAttendance').click();await page.locator('#amLoading').waitFor({state:'visible'});await page.locator('#amContent').waitFor({state:'visible'});
 assert.equal(await page.locator('.m3-person').count(),2);
 const rows=page.locator('#amRows > tr:not(.m3-row-detail)');
 assert.equal(await rows.count(),30);
 assert.equal(await rows.last().locator('select').isDisabled(),true);
 assert.equal(await page.locator('#amVerify').isDisabled(),true);
 if(role==='manager'){
 const first=rows.first(),second=rows.nth(1);
 await first.locator('select').selectOption('custom');
 assert.equal(await page.locator('#amRows .m3-row-detail').first().locator('input[type=time]').first().inputValue(),'');
 await first.locator('select').selectOption('morning');
 await second.locator('select').selectOption('off');
 await page.locator('#amVerify').click();
 await page.waitForFunction(()=>document.querySelector('#amMessage').textContent.includes('แก้ไข'));
 assert.equal((await page.evaluate(()=>window.__calls)).filter(x=>x.name==='save_attendance').length,0);
 await page.locator('#amRows .m3-row-detail').nth(1).locator('input[type=text]').fill('ทดสอบหยุด');
 await page.locator('#amVerify').click();
 await page.waitForFunction(()=>document.querySelector('#amMessage').textContent.includes('สำเร็จ 2 วัน'));
 const calls=await page.evaluate(()=>window.__calls);
 assert.equal(calls.filter(x=>x.name==='save_attendance').length,2);
 assert.equal(calls.filter(x=>x.name==='transition_attendance').length,2);
 assert.equal(await page.locator('#amApprove').isVisible(),false);
 }else{
 await page.locator('#amApprove').click();await page.waitForFunction(()=>document.querySelector('#amMessage').textContent.includes('สำเร็จ 1 วัน'));
 const calls=await page.evaluate(()=>window.__calls);
 assert.equal(calls.find(x=>x.name==='transition_attendance').args.p_action,'approve');
 }
 await page.locator('#amDept').selectOption('dept2');await page.locator('#amEmpty').waitFor({state:'visible'});assert.equal(await page.locator('#amSchedule').isVisible(),true);
 await page.locator('#amSchedule').click();await page.locator('#schedulerView').waitFor({state:'visible'});assert.equal(await page.locator('#scheduleDept').inputValue(),'dept2');
 await page.locator('#tabStaff').click();await page.locator('#employeeView').waitFor({state:'visible'});
 assert.deepEqual(errors,[]);await page.close();
 }
 console.log('PASS desktop Manager + mobile Owner: load, validate, save, approve, empty, navigation');
 }finally{await browser.close();server.close()}})().catch(e=>{console.error(e);process.exit(1)});
