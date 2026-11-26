-- Synthetic PostgreSQL harness only, after migrations.
insert into public.user_profiles(user_id,display_name,role) values
 ('00000000-0000-4000-8000-000000000001','Synthetic owner','owner'),
 ('00000000-0000-4000-8000-000000000002','Synthetic manager','manager');
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
select public.create_staff('EMP-TEST-001','Synthetic','Baseline','','',(select id from public.departments where name='หน้าร้าน'),'Test','daily','2025-01-01','active');
commit;
