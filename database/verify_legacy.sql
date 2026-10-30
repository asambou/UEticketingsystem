-- Run after migrations/002_legacy_continuity.sql. All fixtures roll back.
begin;
insert into auth.users(id,email) values('00000000-0000-4000-8000-000000000090','legacy-test@example.test');
insert into public.profiles(id,name,role) values('00000000-0000-4000-8000-000000000090','LEGACY TEST MANAGER','manager');
insert into public.tickets(id,number,data,created_at,legacy_source) values('00000000-0000-4000-8000-000000000091','TEST-LEGACY-ONLY','{"title":"Legacy fixture","customer":"Example","phone":"","location":"Example","category":"Site Survey","priority":"High","team":"Projects","assignee":"Unprovisioned legacy technician","due":"","channel":"Not recorded","description":"Original fixture","status":"Resolved","resolution":"Original technician action","satisfaction":"Not Yet Confirmed","materials":[]}',null,'{"source_ticket_id":"TEST-LEGACY-ONLY","ticket":{"Created Date/Time":"invalid source date"}}');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000090',true);
set local role authenticated;
do $$ declare t public.tickets; r public.tickets; rejected boolean; begin
 select * into t from public.tickets where number='TEST-LEGACY-ONLY';
 r:=public.save_ticket(t.id,1,t.data,'Continue original ticket','Internal Follow-up');
 if r.version<>2 or r.data->>'assignee'<>'Unprovisioned legacy technician' or r.created_at is not null or r.legacy_source<>t.legacy_source then raise exception 'Legacy provenance/assignment was not preserved'; end if;
 rejected:=false;
 begin
  perform public.save_ticket(r.id,2,r.data||'{"assignee":"Another unprovisioned name"}','Reassign fixture','Internal Follow-up');
 exception when others then rejected:=true; end;
 if not rejected then raise exception 'New unprovisioned assignment should be rejected'; end if;
 rejected:=false;
 begin
  perform public.save_ticket('00000000-0000-4000-8000-000000000092',0,t.data||'{"assignee":""}','Create without date','Internal Follow-up');
 exception when others then rejected:=true; end;
 if not rejected then raise exception 'New tickets still require a valid due date'; end if;
 rejected:=false;
 begin
  perform public.save_ticket(r.id,2,r.data||'{"legacy_source":{"ticket":{}}}','Tamper with provenance','Internal Follow-up');
 exception when others then rejected:=true; end;
 if not rejected then raise exception 'Client must not be able to replace provenance'; end if;
end $$;
reset role;
rollback;
select 'PASS: legacy tickets remain editable without inventing dates/accounts; original provenance stays immutable; new assignment/date rules remain enforced.' as result;
