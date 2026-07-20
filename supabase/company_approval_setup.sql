-- Run this in the Supabase SQL editor after the previous setup files.
-- Adds an approval workflow for company listings, and fixes a real gap:
-- there was no INSERT policy on public.companies at all, so nobody —
-- not even the admin — could actually create a new company row under RLS
-- until now (the "Add company" admin button and "List your company" both
-- rely on this).

alter table public.companies
  add column if not exists status text not null default 'approved';
  -- 'pending' | 'approved' | 'declined'. Existing rows (already-seeded
  -- companies, anything admin already added) default to 'approved' so
  -- nothing already live gets hidden.

drop policy if exists "Signed-in users can submit a company" on public.companies;
create policy "Signed-in users can submit a company" on public.companies
  for insert with check (auth.uid() is not null);
