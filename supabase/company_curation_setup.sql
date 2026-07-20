-- Run this in the Supabase SQL editor after the previous setup files.
-- Adds homepage curation (featured + drag order), member-count stats, and
-- the "Easy onboarding" stamp toggle to companies. No new RLS needed — the
-- existing "Anyone can view companies" (public read) and "Admin can update
-- any company" policies already cover these new columns.

alter table public.companies
  add column if not exists featured_on_home boolean not null default false,
  add column if not exists home_order integer not null default 0,
  add column if not exists active_members integer not null default 0,
  add column if not exists total_members integer not null default 0,
  add column if not exists has_stamp boolean not null default false;
