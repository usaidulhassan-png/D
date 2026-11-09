-- Central licensing foundation. Run after creating the Supabase project.
-- Direct browser access is denied; only the license Edge Function uses service role.
create sequence if not exists public.da_customer_serial_seq start 1;

create table if not exists public.da_license_customers (
  id uuid primary key default gen_random_uuid(),
  serial_id text not null unique,
  auth_user_id uuid not null unique references auth.users(id) on delete restrict,
  status text not null default 'pending' check (status in ('active','inactive','blocked','pending')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_verified_at timestamptz
);
alter table public.da_license_customers alter column status set default 'pending';
alter table public.da_license_customers drop constraint if exists da_license_customers_status_check;
alter table public.da_license_customers add constraint da_license_customers_status_check check (status in ('active','inactive','blocked','pending'));

create table if not exists public.da_license_devices (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.da_license_customers(id) on delete restrict,
  installation_id uuid not null,
  status text not null default 'active' check (status in ('active','inactive','blocked','pending')),
  first_seen_at timestamptz not null default now(),
  last_verified_at timestamptz,
  last_activity_at timestamptz,
  approved_at timestamptz,
  unique(customer_id, installation_id)
);

create table if not exists public.da_license_owner_accounts (
  auth_user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.da_license_events (
  id bigint generated always as identity primary key,
  customer_id uuid references public.da_license_customers(id) on delete set null,
  device_id uuid references public.da_license_devices(id) on delete set null,
  event_type text not null,
  created_at timestamptz not null default now(),
  detail jsonb not null default '{}'::jsonb
);

alter table public.da_license_customers enable row level security;
alter table public.da_license_devices enable row level security;
alter table public.da_license_owner_accounts enable row level security;
alter table public.da_license_events enable row level security;
revoke all on public.da_license_customers, public.da_license_devices,
  public.da_license_owner_accounts, public.da_license_events from anon, authenticated;
grant usage, select on sequence public.da_customer_serial_seq to service_role;
grant all on public.da_license_customers, public.da_license_devices,
  public.da_license_owner_accounts, public.da_license_events to service_role;

create or replace function public.da_next_customer_serial()
returns text language sql security definer set search_path = '' as $$
  select 'DA-' || lpad(nextval('public.da_customer_serial_seq')::text, 6, '0');
$$;
revoke all on function public.da_next_customer_serial() from public, anon, authenticated;
grant execute on function public.da_next_customer_serial() to service_role;

-- After creating your owner Auth user, add that user's UUID here:
-- insert into public.da_license_owner_accounts(auth_user_id)
-- values ('YOUR-AUTH-USER-UUID');
