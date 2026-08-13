-- Run this in the Supabase SQL editor after facebook_listings_setup.sql.
-- Adds:
--   1. Per-company "auto-accept applications" toggle — when on, a new
--      applicant is accepted immediately instead of sitting in Pending.
--      Enforced server-side with a trigger (not just client logic) so it
--      can't be bypassed by a crafted insert.
--   2. Listing media fields (title, description, photo) so a company can
--      brief a partner on exactly what to post — the "Post your Facebook
--      listing" walkthrough renders these as a mock Marketplace card.

alter table public.companies
  add column if not exists auto_accept_applications boolean not null default false,
  add column if not exists listing_title text,
  add column if not exists listing_description text,
  add column if not exists listing_photo_url text;

create or replace function public.handle_application_auto_accept()
returns trigger as $$
begin
  if new.status = 'pending' and exists (
    select 1 from public.companies c
    where c.id = new.company_id and c.auto_accept_applications = true
  ) then
    new.status := 'accepted';
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists trg_application_auto_accept on public.applications;
create trigger trg_application_auto_accept
  before insert on public.applications
  for each row execute function public.handle_application_auto_accept();

-- Storage bucket for listing photos (public read; only an active rep of the
-- company, or the admin, may upload/replace — same pattern as company-logos).
insert into storage.buckets (id, name, public)
values ('listing-photos', 'listing-photos', true)
on conflict (id) do nothing;

drop policy if exists "Public read for listing photos" on storage.objects;
create policy "Public read for listing photos" on storage.objects
  for select using (bucket_id = 'listing-photos');

drop policy if exists "Reps can upload their company's listing photo" on storage.objects;
create policy "Reps can upload their company's listing photo" on storage.objects
  for insert with check (
    bucket_id = 'listing-photos' and (
      exists (
        select 1 from public.company_certifications cc
        where cc.company_id::text = (storage.foldername(name))[1]
          and cc.user_id = auth.uid() and cc.status = 'active'
      )
      or auth.jwt() ->> 'email' = 'sadasy.b@gmail.com'
    )
  );

drop policy if exists "Reps can replace their company's listing photo" on storage.objects;
create policy "Reps can replace their company's listing photo" on storage.objects
  for update using (
    bucket_id = 'listing-photos' and (
      exists (
        select 1 from public.company_certifications cc
        where cc.company_id::text = (storage.foldername(name))[1]
          and cc.user_id = auth.uid() and cc.status = 'active'
      )
      or auth.jwt() ->> 'email' = 'sadasy.b@gmail.com'
    )
  );
