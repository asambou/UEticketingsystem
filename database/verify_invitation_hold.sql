begin;
select set_config('request.jwt.claim.sub',(select id::text from public.profiles where active and role='admin' limit 1),true);
set local role authenticated;
do $$ begin
 if (select approved from public.energy_invitation_release) then raise exception 'Invitations unexpectedly released'; end if;

end $$;
select public.energy_stage_invitation('fixture@example.invalid','Fixture','technician','Rollback test',true);
select public.energy_set_invitation_release(true,'Rollback-only test approval');
select public.energy_stage_invitation('fixture@example.invalid','Fixture','manager','Edited',false);
do $$begin if (select approved from public.energy_invitation_release) then raise exception 'Edit did not restore hold'; end if; end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
do $$begin
 if exists(select 1 from public.energy_invitation_queue) then raise exception 'Outsider can read queue'; end if;
 begin perform public.energy_set_invitation_release(true,'Forbidden');raise exception 'Outsider released batch';exception when insufficient_privilege then null;end;
 begin perform public.energy_stage_invitation('outsider@example.invalid','Outsider','admin','',true);raise exception 'Outsider staged account';exception when insufficient_privilege then null;end;
end $$;
rollback;
select (select count(*) from public.energy_invitation_queue) as pending_entries,(select count(*) from public.energy_invitation_queue where included) as included,(select approved from public.energy_invitation_release) as released,(select count(*) from public.profiles) as approved_accounts;
