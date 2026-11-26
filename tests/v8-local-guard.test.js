const assert=require('node:assert/strict'),G=require('../scripts/local-v8-guard.cjs');
for(const endpoint of ['unix:///var/run/docker.sock','unix:///home/me/.docker/run/docker.sock','npipe:////./pipe/docker_engine','npipe:////./pipe/dockerDesktopLinuxEngine'])assert.equal(G.localDockerEndpoint(endpoint),true);
for(const endpoint of ['ssh://root@server','tcp://127.0.0.1:2375','https://remote.example','npipe:////remote/pipe/docker_engine','',null])assert.equal(G.localDockerEndpoint(endpoint),false);
assert.deepEqual(G.localSupabaseEnv({PATH:'x',SUPABASE_ACCESS_TOKEN:'test',SUPABASE_DB_URL:'test',supabase_workdir:'test',DOCKER_HOST:'local'}),{PATH:'x',DOCKER_HOST:'local'});
console.log('PASS local Docker and cloud-environment guards');
