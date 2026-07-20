-- Run this once in the Supabase SQL editor (Project > SQL Editor > New query)
-- to support the "Start Building" / Create hub feature in index.html.

-- 1. Verification fields + a flag tracking whether someone has completed the
--    "List your company" step (that modal doesn't persist to a table itself,
--    it's a lead-gen form, so we just track that they finished it).
alter table public.profiles
  add column if not exists website text,
  add column if not exists instagram text,
  add column if not exists linkedin text,
  add column if not exists has_listed_company boolean not null default false;

-- 2. Real, DB-backed company listings. Only used for the sales-certification
--    / "edit your assigned company's listing" flow for now.
create table if not exists public.companies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  stage text,
  roles text[] not null default '{}',
  comp text[] not null default '{}',
  logo_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.companies enable row level security;

drop policy if exists "Anyone can view companies" on public.companies;
create policy "Anyone can view companies" on public.companies
  for select using (true);

-- 3. Who's certified to represent (and edit) which company.
create table if not exists public.company_certifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  status text not null default 'pending', -- 'pending' | 'active'
  created_at timestamptz not null default now(),
  unique (user_id, company_id)
);

alter table public.company_certifications enable row level security;

drop policy if exists "Users can view their own certifications" on public.company_certifications;
create policy "Users can view their own certifications" on public.company_certifications
  for select using (auth.uid() = user_id);

drop policy if exists "Users can request a certification" on public.company_certifications;
create policy "Users can request a certification" on public.company_certifications
  for insert with check (auth.uid() = user_id);

-- Active reps (status = 'active') can edit the company they're certified for.
drop policy if exists "Active reps can update their assigned company" on public.companies;
create policy "Active reps can update their assigned company" on public.companies
  for update using (
    exists (
      select 1 from public.company_certifications cc
      where cc.company_id = companies.id
        and cc.user_id = auth.uid()
        and cc.status = 'active'
    )
  );

-- 4. Seed Custom514 (the example company used throughout the site's
--    marketing copy) and grant Sada Sy an active certification on it, so he
--    can edit its listing from the "Start a sales profile" panel.
insert into public.companies (name, description, stage, roles, comp, logo_url)
select 'Custom514', 'Custom signage and physical brand experiences', 'Growing',
       array['Sales','Design','Videography'], array['Paid','Commission','Experience'],
       '/assets/logos/custom514.png'
where not exists (select 1 from public.companies where name = 'Custom514');

insert into public.company_certifications (user_id, company_id, status)
select u.id, c.id, 'active'
from auth.users u, public.companies c
where u.email = 'sadasy.b@gmail.com' and c.name = 'Custom514'
on conflict (user_id, company_id) do update set status = 'active';
