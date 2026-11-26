'use strict';
const {spawnSync}=require('node:child_process');
function localDockerEndpoint(endpoint){return typeof endpoint==='string'&&(/^(?:unix:\/\/\/[^\r\n]+|npipe:\/\/\/\/\.\/pipe\/[A-Za-z0-9_.-]+)$/.test(endpoint))}
function assertDockerLocal(){
 if(process.env.DOCKER_HOST&&!localDockerEndpoint(process.env.DOCKER_HOST))throw Error('Remote Docker endpoint refused; use a local engine.');
 const run=args=>{const q=spawnSync('docker',args,{encoding:'utf8',stdio:['ignore','pipe','pipe']});if(q.error||q.status!==0)throw Error('Local Docker CLI/engine is required.');return q.stdout.trim()};
 if(!process.env.DOCKER_HOST||process.env.DOCKER_CONTEXT){const ctx=run(['context','show']);const endpoint=JSON.parse(run(['context','inspect',ctx,'--format','{{json .Endpoints.docker.Host}}']));if(!localDockerEndpoint(endpoint))throw Error('Remote Docker context refused; use a local engine.')}
 return true;
}
function localSupabaseEnv(env){return Object.fromEntries(Object.entries(env).filter(([k])=>!/^SUPABASE_/i.test(k)))}
module.exports={localDockerEndpoint,assertDockerLocal,localSupabaseEnv};
