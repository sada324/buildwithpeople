-- Run this in the Supabase SQL editor after the previous setup files.
-- Adds:
--   1. Per-company listing price + commission structure, settable by a
--      company's active reps (via Manage company > Listings) or the admin
--      (via the admin "Edit company listing" modal).
--   2. listing_tasks — one row per (company, partner) tracking that
--      partner's Facebook listing for that company through
--      pending -> submitted -> verified/rejected. This powers the
--      "Your companies" walkthrough on the dashboard: an empty circle next
--      to a company fills in black once their listing_tasks row for it is
--      verified.
--   3. The partner's commission balance shown at the top of the dashboard
--      is just sum(amount) over their verified listing_tasks rows —
--      computed client-side, no extra schema needed for it.

alter table public.companies
  add column if not exists listing_price numeric,
  add column if not exists commission_type text not null default 'percent', -- 'percent' | 'flat'
  add column if not exists commission_value numeric,
  add column if not exists commission_notes text;

create table if not exists public.listing_tasks (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending', -- 'pending' | 'submitted' | 'verified' | 'rejected'
  listing_url text,
  note text,
  amount numeric,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  submitted_at timestamptz,
  verified_at timestamptz,
  verified_by uuid references auth.users(id),
  unique (company_id, user_id)
);

alter table public.listing_tasks enable row level security;

drop policy if exists "Partners can view their own listing tasks" on public.listing_tasks;
create policy "Partners can view their own listing tasks" on public.listing_tasks
  for select using (auth.uid() = user_id);

drop policy if exists "Reps can view listing tasks for their company" on public.listing_tasks;
create policy "Reps can view listing tasks for their company" on public.listing_tasks
  for select using (
    exists (
      select 1 from public.company_certifications cc
      where cc.company_id = listing_tasks.company_id
        and cc.user_id = auth.uid() and cc.status = 'active'
    )
    or auth.jwt() ->> 'email' = 'sadasy.b@gmail.com'
  );

drop policy if exists "Partners can create their own listing task" on public.listing_tasks;
create policy "Partners can create their own listing task" on public.listing_tasks
  for insert with check (auth.uid() = user_id);

-- A partner can edit their own submission up until it's verified (so they
-- can fix a rejected one and resubmit) — but not touch it once approved.
drop policy if exists "Partners can update their own unverified listing task" on public.listing_tasks;
create policy "Partners can update their own unverified listing task" on public.listing_tasks
  for update using (auth.uid() = user_id and status in ('pending', 'submitted', 'rejected'))
  with check (auth.uid() = user_id);

-- The company's active reps (or the admin) do the actual checking —
-- approve (verify, with the commission amount owed) or reject.
drop policy if exists "Reps can review listing tasks for their company" on public.listing_tasks;
create policy "Reps can review listing tasks for their company" on public.listing_tasks
  for update using (
    exists (
      select 1 from public.company_certifications cc
      where cc.company_id = listing_tasks.company_id
        and cc.user_id = auth.uid() and cc.status = 'active'
    )
    or auth.jwt() ->> 'email' = 'sadasy.b@gmail.com'
  );
