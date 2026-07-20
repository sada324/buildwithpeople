-- Run this in the Supabase SQL editor after the previous setup files.
-- Adds read-tracking so the Messages panel can show an unread dot.
-- No new RLS needed — the existing "Participants can update conversation
-- timestamp" policy already lets a contributor or an active rep update
-- these columns on a conversation they're part of.

alter table public.conversations
  add column if not exists user_last_read_at timestamptz,
  add column if not exists rep_last_read_at timestamptz;
