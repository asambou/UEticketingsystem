-- Unique Group Service Desk · run once in the Supabase SQL Editor.
-- No real customer data or email directory is seeded.
begin;
create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 name text not null unique check(length(name) between 1 and 120),
 role text not null check(role in ('admin','manager','dispatcher','technician')),
 active boolean not null default true
);
alter table public.profiles enable row level security;
create sequence public.ticket_number_seq;
create table public.tickets (
 id uuid primary key,
 number text not null unique,
 data jsonb not null,
 version integer not null default 1,
 created_at timestamptz not null default now(),
 events jsonb not null default '[]'::jsonb
);
alter table public.tickets enable row level security;
-- Active company staff can read all service tickets for coordination.
-- Account and role administration is restricted to Supabase administrators.
create function public.is_active_staff() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles where id=auth.uid() and active);
$$;
revoke all on function public.is_active_staff() from public;
grant execute on function public.is_active_staff() to authenticated;
create policy staff_read_profiles on public.profiles for select to authenticated using(public.is_active_staff());
create policy staff_read_tickets on public.tickets for select to authenticated using(public.is_active_staff());
revoke all on public.profiles, public.tickets from anon, authenticated;
grant select on public.profiles, public.tickets to authenticated;
-- All writes pass through this RPC. Role checks, optimistic concurrency,
-- server-generated IDs/numbers, and an append-only event are one transaction.
create function public.save_ticket(p_id uuid,p_expected_version integer,p_data jsonb,p_note text,p_type text)
returns public.tickets language plpgsql security definer set search_path='' as $$
declare
 actor public.profiles;
 old_ticket public.tickets;
 result public.tickets;
 managing boolean;
 k text;
 required_keys text[] := array['title','customer','phone','location','category','priority','team','assignee','due','channel','description','status','resolution','satisfaction','materials'];
begin
 select * into actor from public.profiles where id=auth.uid() and active;
 if not found then raise exception 'Active staff membership required' using errcode='42501'; end if;
 managing := actor.role in ('admin','manager','dispatcher');
 if p_id is null or p_expected_version is null or p_expected_version < 0 then raise exception 'Invalid ticket identity/version'; end if;
 if p_note is null or length(trim(p_note)) < 1 or length(p_note)>10000 then raise exception 'A work note is required (maximum 10000 characters)'; end if;
 if p_type is null or p_type not in ('Call','WhatsApp','Email','Site Visit','Internal Follow-up','Escalation') then raise exception 'Invalid update type'; end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or not(p_data ?& required_keys) then raise exception 'Incomplete ticket fields'; end if;
 for k in select jsonb_object_keys(p_data) loop
  if not(k=any(required_keys)) then raise exception 'Unknown ticket field: %',k; end if;
  if k<>'materials' and jsonb_typeof(p_data->k)<>'string' then raise exception 'Invalid field type: %',k; end if;
 end loop;
 if length(trim(p_data->>'title')) not between 1 and 160 or length(trim(p_data->>'customer')) not between 1 and 120 or length(trim(p_data->>'location')) not between 1 and 180 or length(trim(p_data->>'description')) not between 1 and 6000 or length(p_data->>'resolution')>6000 or length(p_data->>'phone')>40 then raise exception 'Ticket field length is invalid'; end if;
 if p_data->>'status' not in ('Open','Assigned','In Progress','Pending Customer','Pending Parts','Escalated','Resolved - Pending Confirmation','Resolved','Closed','Cancelled') then raise exception 'Invalid status'; end if;
 if p_data->>'priority' not in ('Critical','High','Medium','Low') then raise exception 'Invalid priority'; end if;
 if p_data->>'satisfaction' not in ('Satisfied','Partly Satisfied','Not Satisfied','No Response','Not Yet Confirmed') then raise exception 'Invalid satisfaction'; end if;
 if p_data->>'team' not in ('Technical','Projects','Customer Service','Sales / Admin','Operations') then raise exception 'Invalid team'; end if;
 if p_data->>'channel' not in ('Call','WhatsApp','Email','Site Visit','Internal Follow-up','Escalation') then raise exception 'Invalid channel'; end if;
 if (p_data->>'due') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'A valid follow-up date is required'; end if;
 perform (p_data->>'due')::date;
 if p_data->>'assignee'<>'' and not exists(select 1 from public.profiles where name=p_data->>'assignee' and active) then raise exception 'Assignee must be active staff'; end if;
 if p_data->>'status'='Assigned' and p_data->>'assignee'='' then raise exception 'An assigned ticket needs an assignee'; end if;
 if p_data->>'status' in ('Resolved - Pending Confirmation','Resolved','Closed') and length(trim(p_data->>'resolution'))=0 then raise exception 'Resolution summary required'; end if;
 if p_data->>'status'='Closed' and p_data->>'satisfaction'='Not Yet Confirmed' then raise exception 'Customer feedback or No Response required before closure'; end if;
 if jsonb_typeof(p_data->'materials')<>'array' or jsonb_array_length(p_data->'materials')>1000 then raise exception 'Invalid materials list'; end if;
 if exists(select 1 from jsonb_array_elements(p_data->'materials') m where jsonb_typeof(m)<>'object' or not(m ?& array['name','unit','qty']) or jsonb_typeof(m->'name')<>'string' or jsonb_typeof(m->'unit')<>'string' or jsonb_typeof(m->'qty')<>'number') then raise exception 'Invalid material record'; end if;
 if exists(select 1 from jsonb_array_elements(p_data->'materials') m where (m->>'qty')::numeric<=0 or (m->>'qty')::numeric>100000) then raise exception 'Invalid material quantity'; end if;
 select * into old_ticket from public.tickets where id=p_id for update;
 if found then
  if old_ticket.version<>p_expected_version then raise exception 'This ticket changed. Close it, refresh the page and try again.' using errcode='40001'; end if;
  if not managing then
   if old_ticket.data->>'assignee'<>actor.name then raise exception 'Only the assigned technician may update this ticket' using errcode='42501'; end if;
   if (p_data - array['status','due','resolution','satisfaction','materials']) <> (old_ticket.data - array['status','due','resolution','satisfaction','materials']) then raise exception 'Only managers can change ticket ownership and intake fields' using errcode='42501'; end if;
   if p_data->>'status' in ('Closed','Cancelled') and p_data->>'status'<>old_ticket.data->>'status' then raise exception 'Only managers can close or cancel tickets' using errcode='42501'; end if;
  end if;
  update public.tickets set data=p_data,version=version+1,events=events||jsonb_build_array(jsonb_build_object('at',now(),'actor',actor.name,'type',p_type,'note',p_note,'changes',p_data)) where id=p_id returning * into result;
 else
  if not managing then raise exception 'Only managers and dispatchers can create tickets' using errcode='42501'; end if;
  if p_expected_version<>0 then raise exception 'Ticket does not exist'; end if;
  insert into public.tickets(id,number,data,events) values(p_id,'UE-TKT-'||to_char(current_date,'YYMMDD')||'-'||lpad(nextval('public.ticket_number_seq')::text,6,'0'),p_data,jsonb_build_array(jsonb_build_object('at',now(),'actor',actor.name,'type',p_type,'note',p_note,'changes',p_data))) returning * into result;
 end if;
 return result;
end;
$$;
revoke all on function public.save_ticket(uuid,integer,jsonb,text,text) from public;
grant execute on function public.save_ticket(uuid,integer,jsonb,text,text) to authenticated;
commit;
