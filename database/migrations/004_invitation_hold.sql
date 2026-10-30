begin;
create table public.energy_invitation_queue(email text primary key,name text not null,role text not null check(role in('admin','manager','dispatcher','technician')),notes text not null default '',included boolean not null default true,status text not null default 'pending' check(status in('pending','sent')),updated_at timestamptz not null default now());
create table public.energy_invitation_release(id boolean primary key default true check(id),approved boolean not null default false,approval_reference text not null default '',approved_by uuid,approved_at timestamptz);
insert into public.energy_invitation_release(id) values(true);
alter table public.energy_invitation_queue enable row level security;
alter table public.energy_invitation_release enable row level security;
revoke all on public.energy_invitation_queue,public.energy_invitation_release from anon,authenticated;
grant select on public.energy_invitation_queue,public.energy_invitation_release to authenticated;
create policy admins_queue on public.energy_invitation_queue for select to authenticated using(public.is_energy_admin());
create policy admins_release on public.energy_invitation_release for select to authenticated using(public.is_energy_admin());
create function public.energy_stage_invitation(p_email text,p_name text,p_role text,p_notes text,p_included boolean) returns void language plpgsql security definer set search_path='' as $$begin
 if not public.is_energy_admin() then raise exception 'Administrator required' using errcode='42501'; end if;
 if p_email is null or p_email!~'^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or length(p_email)>254 or p_name is null or length(trim(p_name)) not between 1 and 120 or p_role is null or p_role not in('admin','manager','dispatcher','technician') or p_included is null then raise exception 'Valid staff details required'; end if;
 if exists(select 1 from auth.users u join public.profiles p on p.id=u.id where lower(u.email)=lower(trim(p_email))) then raise exception 'Already approved; use member controls'; end if;
 insert into public.energy_invitation_queue(email,name,role,notes,included) values(lower(trim(p_email)),trim(p_name),p_role,coalesce(p_notes,''),p_included) on conflict(email) do update set name=excluded.name,role=excluded.role,notes=excluded.notes,included=excluded.included,updated_at=now() where energy_invitation_queue.status='pending';
 -- Any roster edit puts all invitations back on hold for review.
 update public.energy_invitation_release set approved=false,approval_reference='',approved_by=null,approved_at=null;
 insert into public.energy_access_audit(actor,action,detail) values(auth.uid(),'invitation_staged',jsonb_build_object('email',lower(trim(p_email)),'role',p_role,'included',p_included));
end;$$;
create function public.energy_set_invitation_release(p_approved boolean,p_reference text) returns void language plpgsql security definer set search_path='' as $$begin
 if not public.is_energy_admin() then raise exception 'Administrator required' using errcode='42501'; end if;
 if p_approved is null or (p_approved and length(trim(coalesce(p_reference,'')))<5) then raise exception 'Record Operations approval before release'; end if;
 update public.energy_invitation_release set approved=p_approved,approval_reference=case when p_approved then trim(p_reference) else '' end,approved_by=auth.uid(),approved_at=now();
 insert into public.energy_access_audit(actor,action,detail) values(auth.uid(),'invitation_release_changed',jsonb_build_object('approved',p_approved,'reference',p_reference));
end;$$;
create function public.energy_mark_invitation_sent(p_email text) returns void language plpgsql security definer set search_path='' as $$begin
 if not public.is_energy_admin() then raise exception 'Administrator required' using errcode='42501'; end if;
 if not exists(select 1 from auth.users u join public.profiles p on p.id=u.id where lower(u.email)=lower(p_email)) then raise exception 'No approved membership'; end if;
 update public.energy_invitation_queue set status='sent',updated_at=now() where email=lower(p_email);
end;$$;
revoke all on function public.energy_stage_invitation(text,text,text,text,boolean),public.energy_set_invitation_release(boolean,text),public.energy_mark_invitation_sent(text) from public;
grant execute on function public.energy_stage_invitation(text,text,text,text,boolean),public.energy_set_invitation_release(boolean,text),public.energy_mark_invitation_sent(text) to authenticated;
-- Prepare original active directory entries without creating Auth users or profiles.
insert into public.energy_invitation_queue(email,name,role,notes,included)
 select lower(d.email),d.name,case d.source_role when 'Technician' then 'technician' when 'Manager' then 'manager' when 'Operations' then 'manager' when 'Sales/Admin' then 'dispatcher' else 'technician' end,d.notes, d.source_role in('Technician','Manager','Operations','Sales/Admin')
 from public.staff_directory d where d.source_active and not exists(select 1 from auth.users u join public.profiles p on p.id=u.id where lower(u.email)=lower(d.email));
commit;
