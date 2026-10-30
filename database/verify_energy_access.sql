-- Integration tests for approved Energy membership; every fixture rolls back.
begin;
insert into auth.users(id,email) values
('00000000-0000-4000-8000-000000000081','energy-admin@example.test'),
('00000000-0000-4000-8000-000000000082','energy-tech@example.test'),
('00000000-0000-4000-8000-000000000083','energy-outsider@example.test');
insert into public.profiles(id,name,role) values
('00000000-0000-4000-8000-000000000081','ENERGY TEST ADMIN','admin'),
('00000000-0000-4000-8000-000000000082','ENERGY TEST TECH','technician');
insert into public.energy_access_audit(actor,subject,action,detail) values('00000000-0000-4000-8000-000000000081','00000000-0000-4000-8000-000000000083','fixture','{}');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000083',true);
set local role authenticated;
do $$ begin
 if exists(select 1 from public.tickets) or exists(select 1 from public.profiles) or exists(select 1 from public.reference_lists) or exists(select 1 from public.staff_directory) or exists(select 1 from public.energy_access_audit) then raise exception 'Unapproved account can read protected data'; end if;
 begin perform public.admin_approve_member('energy-outsider@example.test','OUTSIDER','admin');raise exception 'Self-approval allowed';exception when insufficient_privilege then null;end;
 begin insert into public.profiles(id,name,role) values(auth.uid(),'OUTSIDER','admin');raise exception 'Direct self-approval allowed';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000082',true);
do $$ begin
 begin perform * from public.list_energy_members();raise exception 'Non-admin membership listing allowed';exception when insufficient_privilege then null;end;
 begin perform public.admin_update_member('00000000-0000-4000-8000-000000000082','admin',true);raise exception 'Non-admin promotion allowed';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000081',true);
select public.admin_approve_member('energy-outsider@example.test','ENERGY TEST APPROVED','technician');
do $$ declare rejected boolean:=false;begin
 begin perform public.admin_update_member(auth.uid(),'technician',false);exception when others then rejected:=true;end;
 if not rejected then raise exception 'Administrator self-removal allowed';end if;
 if not exists(select 1 from public.list_energy_members() where name='ENERGY TEST APPROVED' and active) then raise exception 'Approved member not listed';end if;
end $$;
select public.admin_update_member('00000000-0000-4000-8000-000000000083','technician',false);
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000083',true);
do $$ begin
 if exists(select 1 from public.tickets) or exists(select 1 from public.staff_directory) or exists(select 1 from public.reference_lists) then raise exception 'Deactivated member retains read access';end if;
end $$;
reset role;
set local role anon;
do $$ begin
 begin perform 1 from public.staff_directory;raise exception 'Public directory read allowed';exception when insufficient_privilege then null;end;
 begin perform * from public.list_energy_members();raise exception 'Public member list allowed';exception when insufficient_privilege then null;end;
end $$;
reset role;
rollback;
select 'PASS: outsiders cannot read data, self-approve or promote; only admins manage membership; deactivated users are blocked; all fixtures rolled back.' as result;
