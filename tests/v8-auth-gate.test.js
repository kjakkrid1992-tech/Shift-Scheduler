const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),R=require('../v8/runtime-config.js'),D=require('../v8/staff-dates.js'),A=require('../v8/advance-engine.js');
const root=path.join(__dirname,'..','v8'),html=fs.readFileSync(path.join(root,'index.html'),'utf8'),app=fs.readFileSync(path.join(root,'app.js'),'utf8');
const CAP={version:8,attendance_batch:true,payroll_batch:true};
function createNode(hidden=false){return {hidden,value:'',textContent:'',children:[],classList:{toggle(){}},elements:{department:{replaceChildren(){},add(){}},url:{value:''},key:{value:''}},replaceChildren(...c){this.children=c},append(...c){this.children.push(...c)},addEventListener(){},reset(){}}}
async function check({config={},stored=null,profile=null,cap=CAP,session=true,query='',sdk=true}={}){
 const nodes=new Map();for(const m of html.matchAll(/<([a-z][a-z0-9]*)\b([^>]*\bid="([^"]+)"[^>]*)>/gi)){if(nodes.has(m[3]))throw Error('Duplicate ID '+m[3]);nodes.set(m[3],createNode(/\bhidden\b/.test(m[2])))}
 const document={getElementById:id=>{if(!nodes.has(id))throw Error('Missing DOM id '+id);return nodes.get(id)},createElement:()=>createNode(),querySelectorAll:()=>[]};
 const events=[],storage={getItem:()=>stored,setItem(){},removeItem(){}};
 const db={auth:{onAuthStateChange(){},getSession:async()=>({data:{session:session?{user:{id:'u'}}:null}})},from(table){events.push(table);const q={select(){return q},eq(){return q},maybeSingle:async()=>({data:profile}),order:async()=>({data:[]})};return q},rpc:async name=>{events.push(name);return {data:cap,error:cap?null:{message:'Missing function'}}}};
 const window={StaffDates:D,AdvanceEngine:A,V8Runtime:R,STAFF_CONFIG:config};
 for(const key of ['LegacyPage','PayrollPage','AdvancePage','AttendancePage','SchedulerPage'])window[key]={reset(){},staffTab(){return true}};
 if(sdk)window.supabase={createClient(url,key,options){events.push(['connect',url,options.auth.persistSession]);return db}};
 const location={search:query,href:'http://127.0.0.1:5501/v8/'+query,replace(){}};
 const source=app.replace(/\ninit\(\);\s*$/,'\nreturn init();');
 if(source===app)throw Error('Startup anchor changed');
 await new Function('window','document','localStorage','location','Option','confirm','URLSearchParams',source)(window,document,storage,location,()=>{},()=>true,URLSearchParams);
 return {nodes,events};
}
async function main(){
 const local={url:'http://127.0.0.1:54321',publishableKey:'sb_publishable_local',localOnly:true},cloud={url:'https://abc.supabase.co',publishableKey:'sb_publishable_cloud'};
 const owner={role:'owner',active:true,display_name:'Synthetic Owner'},manager={role:'manager',active:true,display_name:'Synthetic Manager'};
 const hidden=(x,id)=>x.nodes.get(id).hidden;
 let x=await check();assert.equal(hidden(x,'setup'),false);assert.deepEqual(x.events,[]);
 x=await check({config:local,stored:JSON.stringify(cloud),session:false});assert.equal(hidden(x,'login'),false);assert.equal(hidden(x,'changeConfig'),true);assert.deepEqual(x.events,[['connect',local.url,false]]);
 x=await check({config:local,profile:owner,cap:null});assert.equal(hidden(x,'workspace'),true);assert.equal(x.events.includes('employees'),false);
 x=await check({config:local,profile:{...owner,active:false}});assert.equal(hidden(x,'workspace'),true);assert.equal(x.events.includes('v8_workspace_capabilities'),false);
 x=await check({config:local,profile:{role:'employee',active:true}});assert.equal(hidden(x,'workspace'),true);assert.equal(x.events.includes('employees'),false);
 x=await check({config:local,profile:owner});assert.equal(hidden(x,'workspace'),false);assert.equal(hidden(x,'tabLegacy'),false);assert.equal(hidden(x,'changeConfig'),true);
 x=await check({config:local,profile:manager});assert.equal(hidden(x,'workspace'),false);assert.equal(hidden(x,'tabLegacy'),true);assert.equal(hidden(x,'profileLegacyLoad'),true);
 x=await check({config:cloud,query:'?configure=1'});assert.equal(hidden(x,'setup'),false);assert.deepEqual(x.events,[]);
 x=await check({config:local,sdk:false});assert.equal(hidden(x,'setup'),false);assert.equal(hidden(x,'configForm'),true);
 console.log('PASS actual app startup with isolated transport: setup, local-only, no session, unauthorized, RC2 capability guard, owner/manager and SDK failure');
}
module.exports=main();
