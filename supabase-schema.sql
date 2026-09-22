-- RD Lot Register shared backend (v2 — full account tracking + realtime)
-- Run this in Supabase SQL Editor, then create agent users in Authentication.

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  agent_id text not null unique,
  display_name text not null default '',
  post_office text not null default '',
  commission_rate numeric(5,2) not null default 4.0,
  created_at timestamptz not null default now()
);

create table if not exists public.members (
  id uuid primary key default gen_random_uuid(),
  agent_id uuid not null references public.profiles(id) on delete cascade,
  account_number text not null,
  name text not null,
  monthly_amount numeric(12,2) not null check (monthly_amount > 0),
  interest_rate numeric(5,2) not null default 6.7,
  tenure_months integer not null default 60,
  opening_date date,
  maturity_date date,
  nominee_name text not null default '',
  nominee_relation text not null default '',
  mobile_number text not null default '',
  address text not null default '',
  post_office text not null default '',
  passbook_number text not null default '',
  kyc_status text not null default 'pending' check (kyc_status in ('pending','verified')),
  account_status text not null default 'active' check (account_status in ('active','discontinued','matured','closed')),
  month_paid_upto integer,
  next_due_date text not null default '',
  details text not null default '',
  created_at timestamptz not null default now(),
  unique (agent_id, account_number)
);

-- Safe upgrade path for databases created from the v1 schema
alter table public.members add column if not exists interest_rate numeric(5,2) not null default 6.7;
alter table public.members add column if not exists tenure_months integer not null default 60;
alter table public.members add column if not exists opening_date date;
alter table public.members add column if not exists maturity_date date;
alter table public.members add column if not exists nominee_name text not null default '';
alter table public.members add column if not exists nominee_relation text not null default '';
alter table public.members add column if not exists mobile_number text not null default '';
alter table public.members add column if not exists address text not null default '';
alter table public.members add column if not exists post_office text not null default '';
alter table public.members add column if not exists passbook_number text not null default '';
alter table public.members add column if not exists kyc_status text not null default 'pending';
alter table public.members add column if not exists account_status text not null default 'active';
alter table public.members add column if not exists month_paid_upto integer;
alter table public.members add column if not exists next_due_date text not null default '';
alter table public.profiles add column if not exists post_office text not null default '';
alter table public.profiles add column if not exists commission_rate numeric(5,2) not null default 4.0;

create table if not exists public.payments (
  member_id uuid not null references public.members(id) on delete cascade,
  payment_year integer not null check (payment_year between 2000 and 2200),
  payment_month integer not null check (payment_month between 0 and 11),
  paid boolean not null default false,
  paid_date date,
  default_fee numeric(12,2) not null default 0,
  updated_at timestamptz not null default now(),
  primary key (member_id, payment_year, payment_month)
);

alter table public.payments add column if not exists paid_date date;
alter table public.payments add column if not exists default_fee numeric(12,2) not null default 0;

alter table public.profiles enable row level security;
alter table public.members enable row level security;
alter table public.payments enable row level security;

drop policy if exists "agents read own profile" on public.profiles;
drop policy if exists "agents create own profile" on public.profiles;
drop policy if exists "agents update own profile" on public.profiles;
drop policy if exists "agents read own members" on public.members;
drop policy if exists "agents create own members" on public.members;
drop policy if exists "agents update own members" on public.members;
drop policy if exists "agents delete own members" on public.members;
drop policy if exists "agents read own payments" on public.payments;
drop policy if exists "agents create own payments" on public.payments;
drop policy if exists "agents update own payments" on public.payments;
drop policy if exists "agents delete own payments" on public.payments;

create policy "agents read own profile" on public.profiles for select using (id = auth.uid());
create policy "agents create own profile" on public.profiles for insert with check (id = auth.uid());
create policy "agents update own profile" on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());
create policy "agents read own members" on public.members for select using (agent_id = auth.uid());
create policy "agents create own members" on public.members for insert with check (agent_id = auth.uid());
create policy "agents update own members" on public.members for update using (agent_id = auth.uid()) with check (agent_id = auth.uid());
create policy "agents delete own members" on public.members for delete using (agent_id = auth.uid());
create policy "agents read own payments" on public.payments for select using (exists (select 1 from public.members m where m.id = member_id and m.agent_id = auth.uid()));
create policy "agents create own payments" on public.payments for insert with check (exists (select 1 from public.members m where m.id = member_id and m.agent_id = auth.uid()));
create policy "agents update own payments" on public.payments for update using (exists (select 1 from public.members m where m.id = member_id and m.agent_id = auth.uid()));
create policy "agents delete own payments" on public.payments for delete using (exists (select 1 from public.members m where m.id = member_id and m.agent_id = auth.uid()));

-- Real-time sync: let Supabase push live row changes to every signed-in device.
-- Safe to re-run: skips tables that are already in the publication. RLS above
-- still applies, so each agent only ever receives their own rows.
do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'members') then
    alter publication supabase_realtime add table public.members;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'payments') then
    alter publication supabase_realtime add table public.payments;
  end if;
end $$;

-- After creating an auth user, add its profile:
-- insert into public.profiles (id, agent_id, display_name, post_office, commission_rate)
-- values ('AUTH_USER_UUID', 'POST-OFFICE-AGENT-ID', 'Agent name', 'Home Post Office', 4.0);
