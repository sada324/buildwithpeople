-- Run this in the Supabase SQL editor AFTER create_hub_setup.sql.
-- Adds: profile picture storage, company-logo storage, admin control over
-- every seeded company, and a working messaging system.

-- 1. Avatar column on profiles, website column on companies.
alter table public.profiles
  add column if not exists avatar_url text;

alter table public.companies
  add column if not exists website text;

-- 2. Storage buckets for user avatars and company logos (public read).
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('company-logos', 'company-logos', true)
on conflict (id) do nothing;

drop policy if exists "Public read for avatars and logos" on storage.objects;
create policy "Public read for avatars and logos" on storage.objects
  for select using (bucket_id in ('avatars', 'company-logos'));

-- Avatars are uploaded to a path like "{user_id}/filename.jpg" — only the
-- owning user may write into their own folder.
drop policy if exists "Users can upload their own avatar" on storage.objects;
create policy "Users can upload their own avatar" on storage.objects
  for insert with check (
    bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "Users can replace their own avatar" on storage.objects;
create policy "Users can replace their own avatar" on storage.objects
  for update using (
    bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Company logos are uploaded to a path like "{company_id}/filename.jpg" —
-- only an active certified rep (or the admin) for that company may write.
drop policy if exists "Reps can upload their company's logo" on storage.objects;
create policy "Reps can upload their company's logo" on storage.objects
  for insert with check (
    bucket_id = 'company-logos' and (
      exists (
        select 1 from public.company_certifications cc
        where cc.company_id::text = (storage.foldername(name))[1]
          and cc.user_id = auth.uid() and cc.status = 'active'
      )
      or auth.jwt() ->> 'email' = 'sadasy.b@gmail.com'
    )
  );

drop policy if exists "Reps can replace their company's logo" on storage.objects;
create policy "Reps can replace their company's logo" on storage.objects
  for update using (
    bucket_id = 'company-logos' and (
      exists (
        select 1 from public.company_certifications cc
        where cc.company_id::text = (storage.foldername(name))[1]
          and cc.user_id = auth.uid() and cc.status = 'active'
      )
      or auth.jwt() ->> 'email' = 'sadasy.b@gmail.com'
    )
  );

-- 3. Give the admin (Sada Sy) blanket edit rights over every company, not
--    just the ones he holds an explicit certification for.
drop policy if exists "Admin can update any company" on public.companies;
create policy "Admin can update any company" on public.companies
  for update using (auth.jwt() ->> 'email' = 'sadasy.b@gmail.com');

-- 4. Seed the remaining initial companies shown on the dashboard (Custom514
--    was already seeded by create_hub_setup.sql) and certify the admin as an
--    active rep on all of them, so every "Matches for you" card he owns gets
--    an Edit option.
insert into public.companies (name, description, stage, roles, comp, logo_url)
select v.name, v.description, v.stage, v.roles, v.comp, v.logo_url
from (values
  ('LocalFlow', 'Automating customer acquisition for local businesses', 'Growing',
    array['Sales','Development','Marketing'], array['Equity','Commission'], '/assets/logos/localflow.png'),
  ('Studio North', 'A product design studio building physical and digital goods', 'Growing',
    array['Design','Videography','Operations'], array['Paid','Portfolio','Experience'], '/assets/logos/studionorth.png'),
  ('Build With People', 'The team building this platform is hiring too', 'Growing',
    array['Sales','Videography','Cofounder'], array['Paid','Equity','Commission'], null)
) as v(name, description, stage, roles, comp, logo_url)
where not exists (select 1 from public.companies c where c.name = v.name);

insert into public.company_certifications (user_id, company_id, status)
select u.id, c.id, 'active'
from auth.users u
cross join public.companies c
where u.email = 'sadasy.b@gmail.com'
  and c.name in ('Custom514', 'LocalFlow', 'Studio North', 'Build With People')
on conflict (user_id, company_id) do update set status = 'active';

-- 5. Messaging: a conversation is between one contributor and one company.
--    Any active certified rep for that company (the admin, today) can read
--    and reply on the company's behalf.
create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  created_at timestamptz not null default now(),
  last_message_at timestamptz not null default now(),
  unique (user_id, company_id)
);

alter table public.conversations enable row level security;

drop policy if exists "Participants can view their conversations" on public.conversations;
create policy "Participants can view their conversations" on public.conversations
  for select using (
    auth.uid() = user_id
    or exists (
      select 1 from public.company_certifications cc
      where cc.company_id = conversations.company_id
        and cc.user_id = auth.uid() and cc.status = 'active'
    )
  );

drop policy if exists "Contributors can start a conversation" on public.conversations;
create policy "Contributors can start a conversation" on public.conversations
  for insert with check (auth.uid() = user_id);

drop policy if exists "Participants can update conversation timestamp" on public.conversations;
create policy "Participants can update conversation timestamp" on public.conversations
  for update using (
    auth.uid() = user_id
    or exists (
      select 1 from public.company_certifications cc
      where cc.company_id = conversations.company_id
        and cc.user_id = auth.uid() and cc.status = 'active'
    )
  );

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now()
);

alter table public.messages enable row level security;

drop policy if exists "Participants can view messages" on public.messages;
create policy "Participants can view messages" on public.messages
  for select using (
    exists (
      select 1 from public.conversations c
      where c.id = messages.conversation_id
        and (
          c.user_id = auth.uid()
          or exists (
            select 1 from public.company_certifications cc
            where cc.company_id = c.company_id and cc.user_id = auth.uid() and cc.status = 'active'
          )
        )
    )
  );

drop policy if exists "Participants can send messages" on public.messages;
create policy "Participants can send messages" on public.messages
  for insert with check (
    sender_id = auth.uid()
    and exists (
      select 1 from public.conversations c
      where c.id = messages.conversation_id
        and (
          c.user_id = auth.uid()
          or exists (
            select 1 from public.company_certifications cc
            where cc.company_id = c.company_id and cc.user_id = auth.uid() and cc.status = 'active'
          )
        )
    )
  );

-- Optional but recommended: turn on Realtime for instant message delivery.
-- Supabase dashboard > Database > Replication > add the "messages" table to
-- the supabase_realtime publication. The app still works without this —
-- messages just won't appear until the thread is reopened.
