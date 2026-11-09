-- Digital Attendance shared sync schema for Supabase Free.
-- Never put the service_role key in this PWA. Use only the publishable/anon key and authenticated users.
create table if not exists public.da_employees (
  owner_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  name text not null,
  mobile text not null default '',
  active boolean not null default true,
  qr_value text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (owner_id, id)
);

create table if not exists public.da_attendance (
  owner_id uuid not null references auth.users(id) on delete cascade,
  key text not null,
  employee_id text not null,
  employee_name text not null,
  date date not null,
  check_in text not null,
  check_out text,
  status text not null check (status in ('Present','Late','Absent')),
  method text not null check (method in ('Face','QR')),
  check_out_method text check (check_out_method is null or check_out_method in ('Face','QR')),
  device_id text not null,
  updated_at timestamptz not null default now(),
  primary key (owner_id, key),
  unique (owner_id, employee_id, date)
);

create table if not exists public.da_attendance_deletions (
  owner_id uuid not null references auth.users(id) on delete cascade,
  key text not null,
  deleted_at timestamptz not null default now(),
  device_id text not null,
  primary key (owner_id, key)
);

alter table public.da_employees enable row level security;
alter table public.da_attendance enable row level security;
alter table public.da_attendance_deletions enable row level security;
revoke all on public.da_employees, public.da_attendance, public.da_attendance_deletions from anon;
grant select, insert, update, delete on public.da_employees, public.da_attendance, public.da_attendance_deletions to authenticated;

drop policy if exists da_employees_select on public.da_employees;
create policy da_employees_select on public.da_employees for select to authenticated using ((select auth.uid()) = owner_id);
drop policy if exists da_employees_insert on public.da_employees;
create policy da_employees_insert on public.da_employees for insert to authenticated with check ((select auth.uid()) = owner_id);
drop policy if exists da_employees_update on public.da_employees;
create policy da_employees_update on public.da_employees for update to authenticated using ((select auth.uid()) = owner_id) with check ((select auth.uid()) = owner_id);
drop policy if exists da_employees_delete on public.da_employees;
create policy da_employees_delete on public.da_employees for delete to authenticated using ((select auth.uid()) = owner_id);

drop policy if exists da_attendance_select on public.da_attendance;
create policy da_attendance_select on public.da_attendance for select to authenticated using ((select auth.uid()) = owner_id);
drop policy if exists da_attendance_insert on public.da_attendance;
create policy da_attendance_insert on public.da_attendance for insert to authenticated with check ((select auth.uid()) = owner_id);
drop policy if exists da_attendance_update on public.da_attendance;
create policy da_attendance_update on public.da_attendance for update to authenticated using ((select auth.uid()) = owner_id) with check ((select auth.uid()) = owner_id);
drop policy if exists da_attendance_delete on public.da_attendance;
create policy da_attendance_delete on public.da_attendance for delete to authenticated using ((select auth.uid()) = owner_id);

drop policy if exists da_deletions_select on public.da_attendance_deletions;
create policy da_deletions_select on public.da_attendance_deletions for select to authenticated using ((select auth.uid()) = owner_id);
drop policy if exists da_deletions_insert on public.da_attendance_deletions;
create policy da_deletions_insert on public.da_attendance_deletions for insert to authenticated with check ((select auth.uid()) = owner_id);
drop policy if exists da_deletions_update on public.da_attendance_deletions;
create policy da_deletions_update on public.da_attendance_deletions for update to authenticated using ((select auth.uid()) = owner_id) with check ((select auth.uid()) = owner_id);
drop policy if exists da_deletions_delete on public.da_attendance_deletions;
create policy da_deletions_delete on public.da_attendance_deletions for delete to authenticated using ((select auth.uid()) = owner_id);

create index if not exists da_attendance_owner_date_idx on public.da_attendance (owner_id, date);
-- Schema additions for staff schedules, late and absent records. Safe to run on an existing project.
alter table public.da_employees add column if not exists schedule_category text not null default 'peon';
alter table public.da_employees add column if not exists photo_data text;
alter table public.da_employees add column if not exists gender text not null default '';
alter table public.da_employees add column if not exists face_descriptor jsonb;

alter table public.da_attendance alter column check_in set default '';
alter table public.da_attendance alter column check_in drop not null;
alter table public.da_attendance add column if not exists late_minutes integer not null default 0;
alter table public.da_attendance add column if not exists late_seconds integer not null default 0;
alter table public.da_attendance add column if not exists scheduled_time text not null default '';
alter table public.da_attendance add column if not exists grace_minutes integer not null default 0;
alter table public.da_attendance drop constraint if exists da_attendance_status_check;
alter table public.da_attendance add constraint da_attendance_status_check check (status in ('Present','Late','Absent'));
alter table public.da_attendance drop constraint if exists da_attendance_method_check;
alter table public.da_attendance add constraint da_attendance_method_check check (method in ('Face','QR','Manual'));
create table if not exists public.da_settings (
  owner_id uuid not null references auth.users(id) on delete cascade,
  key text not null,
  value jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (owner_id,key)
);
alter table public.da_settings enable row level security;
revoke all on public.da_settings from anon;
grant select,insert,update,delete on public.da_settings to authenticated;
drop policy if exists da_settings_select on public.da_settings;
create policy da_settings_select on public.da_settings for select to authenticated using ((select auth.uid())=owner_id);
drop policy if exists da_settings_insert on public.da_settings;
create policy da_settings_insert on public.da_settings for insert to authenticated with check ((select auth.uid())=owner_id);
drop policy if exists da_settings_update on public.da_settings;
create policy da_settings_update on public.da_settings for update to authenticated using ((select auth.uid())=owner_id) with check ((select auth.uid())=owner_id);
drop policy if exists da_settings_delete on public.da_settings;
create policy da_settings_delete on public.da_settings for delete to authenticated using ((select auth.uid())=owner_id);

-- Enable instant cross-device refresh through Supabase Realtime.
alter table public.da_employees replica identity full;
alter table public.da_attendance replica identity full;
alter table public.da_settings replica identity full;
do $$ begin alter publication supabase_realtime add table public.da_employees; exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.da_attendance; exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.da_settings; exception when duplicate_object then null; end $$;

-- One-company workspace with individual logins, roles and linked devices.
-- The project owner is the workspace key so existing single-owner records can remain in place.
create table if not exists public.da_companies (
  owner_id uuid primary key references auth.users(id) on delete restrict,
  company_name text not null,
  admin_device_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.da_company_memberships (
  owner_id uuid not null references public.da_companies(owner_id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  email text not null default '',
  role text not null check (role in ('company_admin','attendance_operator','report_viewer')),
  permissions jsonb not null default '{}'::jsonb,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  primary key(owner_id,user_id)
);
create table if not exists public.da_company_devices (
  owner_id uuid not null references public.da_companies(owner_id) on delete cascade,
  installation_id text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  device_name text not null default '',
  device_role text not null default 'user' check (device_role in ('admin_offline','user')),
  status text not null default 'active' check (status in ('active','blocked')),
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  primary key(owner_id,installation_id)
);
create table if not exists public.da_attendance_conflicts (
  id bigint generated always as identity primary key,
  resolution_id uuid not null unique default gen_random_uuid(),
  owner_id uuid not null references public.da_companies(owner_id) on delete cascade,
  attendance_key text not null,
  local_record jsonb not null,
  server_record jsonb not null,
  resolution text not null check (resolution in ('pending','kept_local','kept_server')),
  reported_by uuid not null references auth.users(id),
  resolved_by uuid not null references auth.users(id),
  resolved_at timestamptz not null default now()
);
-- Repair older partial conflict-table versions without deleting attendance data.
alter table public.da_attendance_conflicts add column if not exists resolution_id uuid;
update public.da_attendance_conflicts set resolution_id=gen_random_uuid() where resolution_id is null;
alter table public.da_attendance_conflicts alter column resolution_id set default gen_random_uuid();
alter table public.da_attendance_conflicts alter column resolution_id set not null;
create unique index if not exists da_attendance_conflicts_resolution_id_uidx on public.da_attendance_conflicts(resolution_id);
alter table public.da_attendance_conflicts add column if not exists attendance_key text;
alter table public.da_attendance_conflicts add column if not exists local_record jsonb not null default '{}'::jsonb;
alter table public.da_attendance_conflicts add column if not exists server_record jsonb not null default '{}'::jsonb;
alter table public.da_attendance_conflicts add column if not exists resolution text not null default 'pending';
alter table public.da_attendance_conflicts add column if not exists reported_by uuid references auth.users(id);
alter table public.da_attendance_conflicts add column if not exists resolved_by uuid references auth.users(id);
alter table public.da_attendance_conflicts add column if not exists resolved_at timestamptz not null default now();
update public.da_attendance_conflicts set reported_by=owner_id where reported_by is null;
update public.da_attendance_conflicts set resolved_by=owner_id where resolved_by is null;
alter table public.da_attendance_conflicts alter column reported_by set not null;
alter table public.da_attendance_conflicts alter column resolved_by set not null;
alter table public.da_attendance_conflicts drop constraint if exists da_attendance_conflicts_resolution_check;
alter table public.da_attendance_conflicts add constraint da_attendance_conflicts_resolution_check check (resolution in ('pending','kept_local','kept_server'));
create index if not exists da_attendance_conflicts_owner_resolved_idx on public.da_attendance_conflicts(owner_id,resolved_at desc);

create or replace function public.da_can_access_workspace(p_owner uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.da_company_memberships m where m.owner_id=p_owner and m.user_id=(select auth.uid()) and m.active)
$$;
create or replace function public.da_has_permission(p_owner uuid, p_permission text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.da_company_memberships m where m.owner_id=p_owner and m.user_id=(select auth.uid()) and m.active and
    (m.role='company_admin' or coalesce((m.permissions->>p_permission)::boolean,false)))
$$;
create or replace function public.da_bootstrap_company(p_company_name text, p_installation_id text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare uid uuid := (select auth.uid()); company_name_clean text := trim(p_company_name);
begin
  if uid is null then raise exception 'Sign in is required'; end if;
  if length(company_name_clean)<2 or length(company_name_clean)>120 then raise exception 'Company name must be 2 to 120 characters'; end if;
  if p_installation_id !~ '^[0-9a-f-]{36}$' then raise exception 'Valid device ID required'; end if;
  if exists(select 1 from public.da_companies) then raise exception 'This Supabase project already has a company workspace'; end if;
  insert into public.da_companies(owner_id,company_name,admin_device_id) values(uid,company_name_clean,p_installation_id);
  insert into public.da_company_memberships(owner_id,user_id,email,role) values(uid,uid,coalesce((select email from auth.users where id=uid),''),'company_admin');
  insert into public.da_company_devices(owner_id,installation_id,user_id,device_name,device_role) values(uid,p_installation_id,uid,'Admin device','admin_offline');
  return uid;
end $$;
revoke all on function public.da_bootstrap_company(text,text) from public, anon;
grant execute on function public.da_bootstrap_company(text,text) to authenticated;
create or replace function public.da_touch_device(p_owner uuid, p_installation_id text, p_device_name text default '')
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := (select auth.uid()); result jsonb;
begin
  if uid is null or not public.da_can_access_workspace(p_owner) then raise exception 'Company membership required'; end if;
  if p_installation_id !~ '^[0-9a-f-]{36}$' then raise exception 'Valid device ID required'; end if;
  insert into public.da_company_devices(owner_id,installation_id,user_id,device_name,device_role)
  values(p_owner,p_installation_id,uid,left(coalesce(p_device_name,''),160),'user')
  on conflict(owner_id,installation_id) do update set user_id=case when public.da_company_devices.device_role='admin_offline' then public.da_company_devices.user_id else excluded.user_id end,last_seen_at=now(),device_name=case when excluded.device_name='' then public.da_company_devices.device_name else excluded.device_name end;
  select jsonb_build_object('device_role',d.device_role,'status',d.status,'admin_device_id',c.admin_device_id,'role',m.role,'permissions',m.permissions)
    into result from public.da_company_devices d join public.da_companies c using(owner_id) join public.da_company_memberships m on m.owner_id=d.owner_id and m.user_id=uid
    where d.owner_id=p_owner and d.installation_id=p_installation_id;
  return result;
end $$;
revoke all on function public.da_touch_device(uuid,text,text) from public, anon;
grant execute on function public.da_touch_device(uuid,text,text) to authenticated;

alter table public.da_companies enable row level security;
alter table public.da_company_memberships enable row level security;
alter table public.da_company_devices enable row level security;
alter table public.da_attendance_conflicts enable row level security;
revoke all on public.da_companies,public.da_company_memberships,public.da_company_devices,public.da_attendance_conflicts from anon;
grant select,insert,update,delete on public.da_companies,public.da_company_memberships,public.da_company_devices,public.da_attendance_conflicts to authenticated;
drop policy if exists da_companies_select on public.da_companies;
create policy da_companies_select on public.da_companies for select to authenticated using (public.da_can_access_workspace(owner_id));
drop policy if exists da_companies_update on public.da_companies;
create policy da_companies_update on public.da_companies for update to authenticated using (public.da_has_permission(owner_id,'settings.write')) with check (public.da_has_permission(owner_id,'settings.write'));
drop policy if exists da_memberships_select on public.da_company_memberships;
create policy da_memberships_select on public.da_company_memberships for select to authenticated using (user_id=(select auth.uid()) or public.da_has_permission(owner_id,'users.manage'));
drop policy if exists da_memberships_update on public.da_company_memberships;
create policy da_memberships_update on public.da_company_memberships for update to authenticated using (public.da_has_permission(owner_id,'users.manage')) with check (public.da_has_permission(owner_id,'users.manage'));
drop policy if exists da_devices_select on public.da_company_devices;
create policy da_devices_select on public.da_company_devices for select to authenticated using (user_id=(select auth.uid()) or public.da_has_permission(owner_id,'devices.manage'));
drop policy if exists da_devices_insert on public.da_company_devices;
create policy da_devices_insert on public.da_company_devices for insert to authenticated with check (public.da_can_access_workspace(owner_id) and user_id=(select auth.uid()) and device_role='user');
drop policy if exists da_devices_update on public.da_company_devices;
create policy da_devices_update on public.da_company_devices for update to authenticated using (public.da_has_permission(owner_id,'devices.manage')) with check (public.da_has_permission(owner_id,'devices.manage'));
drop policy if exists da_attendance_conflicts_select on public.da_attendance_conflicts;
create policy da_attendance_conflicts_select on public.da_attendance_conflicts for select to authenticated using (reported_by=(select auth.uid()) or public.da_has_permission(owner_id,'attendance.manage'));
drop policy if exists da_attendance_conflicts_insert on public.da_attendance_conflicts;
create policy da_attendance_conflicts_insert on public.da_attendance_conflicts for insert to authenticated with check (public.da_has_permission(owner_id,'attendance.write') and resolution='pending');
drop policy if exists da_attendance_conflicts_update on public.da_attendance_conflicts;
create policy da_attendance_conflicts_update on public.da_attendance_conflicts for update to authenticated using (public.da_has_permission(owner_id,'attendance.manage')) with check (public.da_has_permission(owner_id,'attendance.manage'));
drop function if exists public.da_resolve_attendance_conflict(uuid,text,uuid,text,jsonb);
create or replace function public.da_resolve_attendance_conflict(p_owner uuid,p_key text,p_resolution_id uuid,p_resolution text,p_local_record jsonb default null,p_conflict_id uuid default null)
returns void language plpgsql security definer set search_path = '' as $$
declare previous_record jsonb;
begin
  if not public.da_has_permission(p_owner,'attendance.manage') then raise exception 'Company Admin permission required'; end if;
  if p_resolution not in ('kept_local','kept_server') then raise exception 'Invalid resolution'; end if;
  select to_jsonb(a) into previous_record from public.da_attendance a where a.owner_id=p_owner and a.key=p_key for update;
  if previous_record is null then raise exception 'Attendance record no longer exists'; end if;
  if p_conflict_id is not null then
    update public.da_attendance_conflicts set resolution=p_resolution,resolved_by=(select auth.uid()),resolved_at=now(),server_record=previous_record
    where resolution_id=p_conflict_id and owner_id=p_owner and attendance_key=p_key and resolution='pending';
    if not found then raise exception 'Pending conflict not found or already resolved'; end if;
  else
    insert into public.da_attendance_conflicts(resolution_id,owner_id,attendance_key,local_record,server_record,resolution,reported_by,resolved_by)
    values(p_resolution_id,p_owner,p_key,coalesce(p_local_record,'{}'::jsonb),previous_record,p_resolution,(select auth.uid()),(select auth.uid()))
    on conflict(resolution_id) do nothing;
  end if;
  if p_resolution='kept_local' then
    update public.da_attendance set check_in=coalesce(p_local_record->>'check_in',''),check_out=nullif(p_local_record->>'check_out',''),status=p_local_record->>'status',late_minutes=coalesce((p_local_record->>'late_minutes')::integer,0),late_seconds=coalesce((p_local_record->>'late_seconds')::integer,0),scheduled_time=coalesce(p_local_record->>'scheduled_time',''),grace_minutes=coalesce((p_local_record->>'grace_minutes')::integer,0),method=p_local_record->>'method',check_out_method=nullif(p_local_record->>'check_out_method',''),device_id=coalesce(p_local_record->>'device_id',''),updated_at=now()
    where owner_id=p_owner and key=p_key;
  end if;
end $$;
revoke all on function public.da_resolve_attendance_conflict(uuid,text,uuid,text,jsonb,uuid) from public,anon;
grant execute on function public.da_resolve_attendance_conflict(uuid,text,uuid,text,jsonb,uuid) to authenticated;

-- Replace single-user policies with membership and permission checks.
drop policy if exists da_employees_select on public.da_employees;
create policy da_employees_select on public.da_employees for select to authenticated using (public.da_has_permission(owner_id,'employees.read'));
drop policy if exists da_employees_insert on public.da_employees;
create policy da_employees_insert on public.da_employees for insert to authenticated with check (public.da_has_permission(owner_id,'employees.write'));
drop policy if exists da_employees_update on public.da_employees;
create policy da_employees_update on public.da_employees for update to authenticated using (public.da_has_permission(owner_id,'employees.write')) with check (public.da_has_permission(owner_id,'employees.write'));
drop policy if exists da_employees_delete on public.da_employees;
create policy da_employees_delete on public.da_employees for delete to authenticated using (public.da_has_permission(owner_id,'employees.write'));
drop policy if exists da_attendance_select on public.da_attendance;
create policy da_attendance_select on public.da_attendance for select to authenticated using (public.da_has_permission(owner_id,'attendance.write') or public.da_has_permission(owner_id,'reports.read'));
drop policy if exists da_attendance_insert on public.da_attendance;
create policy da_attendance_insert on public.da_attendance for insert to authenticated with check (public.da_has_permission(owner_id,'attendance.write'));
drop policy if exists da_attendance_update on public.da_attendance;
create policy da_attendance_update on public.da_attendance for update to authenticated using (public.da_has_permission(owner_id,'attendance.write')) with check (public.da_has_permission(owner_id,'attendance.write'));
drop policy if exists da_attendance_delete on public.da_attendance;
create policy da_attendance_delete on public.da_attendance for delete to authenticated using (public.da_has_permission(owner_id,'attendance.manage'));
drop policy if exists da_deletions_select on public.da_attendance_deletions;
create policy da_deletions_select on public.da_attendance_deletions for select to authenticated using (public.da_has_permission(owner_id,'attendance.manage'));
drop policy if exists da_deletions_insert on public.da_attendance_deletions;
create policy da_deletions_insert on public.da_attendance_deletions for insert to authenticated with check (public.da_has_permission(owner_id,'attendance.manage'));
drop policy if exists da_deletions_update on public.da_attendance_deletions;
create policy da_deletions_update on public.da_attendance_deletions for update to authenticated using (public.da_has_permission(owner_id,'attendance.manage')) with check (public.da_has_permission(owner_id,'attendance.manage'));
drop policy if exists da_deletions_delete on public.da_attendance_deletions;
create policy da_deletions_delete on public.da_attendance_deletions for delete to authenticated using (public.da_has_permission(owner_id,'attendance.manage'));
drop policy if exists da_settings_select on public.da_settings;
create policy da_settings_select on public.da_settings for select to authenticated using (public.da_can_access_workspace(owner_id));
drop policy if exists da_settings_insert on public.da_settings;
create policy da_settings_insert on public.da_settings for insert to authenticated with check (public.da_has_permission(owner_id,'settings.write'));
drop policy if exists da_settings_update on public.da_settings;
create policy da_settings_update on public.da_settings for update to authenticated using (public.da_has_permission(owner_id,'settings.write')) with check (public.da_has_permission(owner_id,'settings.write'));
drop policy if exists da_settings_delete on public.da_settings;
create policy da_settings_delete on public.da_settings for delete to authenticated using (public.da_has_permission(owner_id,'settings.write'));

-- Final result: every row below should report installed = true.
select item, installed from (
  values
    ('da_employees table', to_regclass('public.da_employees') is not null),
    ('da_attendance table', to_regclass('public.da_attendance') is not null),
    ('da_settings table', to_regclass('public.da_settings') is not null),
    ('company workspace table', to_regclass('public.da_companies') is not null),
    ('company membership table', to_regclass('public.da_company_memberships') is not null),
    ('company device table', to_regclass('public.da_company_devices') is not null),
    ('workspace bootstrap function', to_regprocedure('public.da_bootstrap_company(text,text)') is not null),
    ('device registration function', to_regprocedure('public.da_touch_device(uuid,text,text)') is not null)
) as setup_check(item, installed);
