-- Database integration tests. Temporary fixtures roll back; no login credentials are created.
begin;
insert into auth.users(id,email) values
('00000000-0000-4000-8000-000000000001','ue-test-manager@example.test'),
('00000000-0000-4000-8000-000000000002','ue-test-tech@example.test'),
('00000000-0000-4000-8000-000000000003','ue-test-other@example.test');
insert into public.profiles(id,name,role) values
('00000000-0000-4000-8000-000000000001','UE TEST MANAGER','manager'),
('00000000-0000-4000-8000-000000000002','UE TEST TECH','technician'),
('00000000-0000-4000-8000-000000000003','UE TEST OTHER','technician');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
set local role authenticated;
select public.save_ticket('00000000-0000-4000-8000-000000000010',0,
'{"title":"Integration test","customer":"Fictional test","phone":"","location":"Test site","category":"Inverter","priority":"High","team":"Technical","assignee":"UE TEST TECH","due":"2026-12-01","channel":"Call","description":"Rollback-only fixture","status":"Assigned","resolution":"","satisfaction":"Not Yet Confirmed","materials":[]}'::jsonb,'Test creation','Internal Follow-up');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
do $$
declare d jsonb; r public.tickets;
begin
 select data into d from public.tickets where id='00000000-0000-4000-8000-000000000010';
 if d is null then raise exception 'FAIL: active staff read'; end if;
 r:=public.save_ticket('00000000-0000-4000-8000-000000000010',1,d||'{"status":"In Progress"}'::jsonb,'Technician progress','Internal Follow-up');
 if r.version<>2 or jsonb_array_length(r.events)<>2 or r.events->1->>'actor'<>'UE TEST TECH' then raise exception 'FAIL: version/history'; end if;
 begin
  perform public.save_ticket(r.id,1,r.data,'Stale update','Call');
  raise exception 'FAIL: stale write allowed';
 exception when serialization_failure then null; end;
 begin
  perform public.save_ticket(r.id,2,r.data||'{"assignee":"UE TEST OTHER"}'::jsonb,'Forbidden assignment','Call');
  raise exception 'FAIL: reassignment allowed';
 exception when insufficient_privilege then null; end;
 begin
  perform public.save_ticket(r.id,2,r.data||'{"status":"Closed","resolution":"Complete","satisfaction":"Satisfied"}'::jsonb,'Forbidden close','Call');
  raise exception 'FAIL: technician closure allowed';
 exception when insufficient_privilege then null; end;
 begin
  update public.tickets set version=99 where id=r.id;
  raise exception 'FAIL: direct update allowed';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',true);
do $$
declare d jsonb;
begin
 select data into d from public.tickets where id='00000000-0000-4000-8000-000000000010';
 begin
  perform public.save_ticket('00000000-0000-4000-8000-000000000010',2,d,'Unassigned update','Call');
  raise exception 'FAIL: unassigned technician update allowed';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
update public.profiles set active=false where id='00000000-0000-4000-8000-000000000003';
set local role authenticated;
do $$ begin
 if exists(select 1 from public.tickets) then raise exception 'FAIL: inactive member can read'; end if;
end $$;
reset role;
set local role anon;
do $$ begin
 begin
  perform 1 from public.tickets;
  raise exception 'FAIL: anonymous ticket read allowed';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
rollback;
select 'PASS: staff reads, assigned technician writes, version conflicts, immutable history, role restrictions, inactive membership and anonymous denial. All fixtures rolled back.' as result;
