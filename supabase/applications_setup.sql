-- Run this in the Supabase SQL editor AFTER create_hub_setup.sql and
-- media_and_messaging_setup.sql. Adds "Apply to this role" + the
-- accept/deny review flow for company owners and certified reps.

create table if not exists public.applications (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  applicant_id uuid not null references auth.users(id) on delete cascade,
  message text,
  status text not null default 'pending', -- 'pending' | 'accepted' | 'denied'
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (company_id, applicant_id)
);

alter table public.applications enable row level security;

drop policy if exists "Applicants can view their own applications" on public.applications;
create policy "Applicants can view their own applications" on public.applications
  for select using (auth.uid() = applicant_id);

drop policy if exists "Applicants can apply" on public.applications;
create policy "Applicants can apply" on public.applications
  for insert with check (auth.uid() = applicant_id);

drop policy if exists "Reps can view applications to their company" on public.applications;
create policy "Reps can view applications to their company" on public.applications
  for select using (
    exists (
      select 1 from public.company_certifications cc
      where cc.company_id = applications.company_id
        and cc.user_id = auth.uid() and cc.status = 'active'
    )
    or auth.jwt() ->> 'email' = 'sadasy.b@gmail.com'
  );

drop policy if exists "Reps can update application status" on public.applications;
create policy "Reps can update application status" on public.applications
  for update using (
    exists (
      select 1 from public.company_certifications cc
      where cc.company_id = applications.company_id
        and cc.user_id = auth.uid() and cc.status = 'active'
    )
    or auth.jwt() ->> 'email' = 'sadasy.b@gmail.com'
  );

-- Accepting/denying an application sends the applicant a message. The
-- existing "Contributors can start a conversation" policy only lets a user
-- create a conversation row for themselves — a rep needs to be able to start
-- one *for the applicant* too, so the accept/deny notification can go out.
drop policy if exists "Reps can start a conversation with an applicant" on public.conversations;
create policy "Reps can start a conversation with an applicant" on public.conversations
  for insert with check (
    exists (
      select 1 from public.company_certifications cc
      where cc.company_id = conversations.company_id
        and cc.user_id = auth.uid() and cc.status = 'active'
    )
    or auth.jwt() ->> 'email' = 'sadasy.b@gmail.com'
  );
