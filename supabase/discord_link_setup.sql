-- Run this in the Supabase SQL editor after the previous setup files.
-- Adds a per-company Discord invite link, settable by a company's active
-- reps (Manage company > Listings) or the admin (Edit company listing).
-- Shown to signed-in members/reps on the company's profile popup — no
-- separate visibility toggle like the website link has, since it's meant
-- to be handed straight to the team.

alter table public.companies
  add column if not exists discord_url text;
