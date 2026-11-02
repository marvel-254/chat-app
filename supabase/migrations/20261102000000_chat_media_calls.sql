-- Profile identity, media storage, and participant-only WebRTC signaling.
alter table public.profiles add column if not exists avatar_url text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('avatars', 'avatars', true, 5242880, array['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/heic', 'image/heif']),
  ('chat-files', 'chat-files', false, 20971520, null)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy "Anyone can view avatars" on storage.objects
  for select using (bucket_id = 'avatars');
create policy "Users upload own avatar" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text
  );
create policy "Users update own avatar" on storage.objects
  for update to authenticated using (
    bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text
  ) with check (
    bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "Conversation members read shared files" on storage.objects
  for select to authenticated using (
    bucket_id = 'chat-files'
    and exists (
      select 1 from public.conversation_participants cp
      where cp.conversation_id::text = (storage.foldername(name))[1]
        and cp.user_id = auth.uid()
    )
  );
create policy "Conversation members upload shared files" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'chat-files'
    and (storage.foldername(name))[2] = auth.uid()::text
    and exists (
      select 1 from public.conversation_participants cp
      where cp.conversation_id::text = (storage.foldername(name))[1]
        and cp.user_id = auth.uid()
    )
  );

-- WebRTC offer/answer/ICE broadcasts are scoped to an existing DM.
create policy "Conversation members receive call signals" on realtime.messages
  for select to authenticated using (
    realtime.topic() like 'call:%'
    and exists (
      select 1 from public.conversation_participants cp
      where cp.conversation_id::text = split_part(realtime.topic(), ':', 2)
        and cp.user_id = auth.uid()
    )
  );
create policy "Conversation members send call signals" on realtime.messages
  for insert to authenticated with check (
    realtime.topic() like 'call:%'
    and exists (
      select 1 from public.conversation_participants cp
      where cp.conversation_id::text = split_part(realtime.topic(), ':', 2)
        and cp.user_id = auth.uid()
    )
  );

drop function if exists public.get_conversations_for_user();
create function public.get_conversations_for_user()
returns table (
  conversation_id uuid,
  created_at timestamptz,
  updated_at timestamptz,
  peer_id uuid,
  peer_username text,
  peer_display_name text,
  peer_avatar_url text,
  last_message text,
  last_message_at timestamptz,
  unread_count bigint
) language sql stable security invoker as $$
  select
    c.id, c.created_at, c.updated_at,
    (select p.id from public.profiles p join public.conversation_participants cp on cp.user_id = p.id
      where cp.conversation_id = c.id and cp.user_id <> auth.uid() limit 1),
    (select p.username from public.profiles p join public.conversation_participants cp on cp.user_id = p.id
      where cp.conversation_id = c.id and cp.user_id <> auth.uid() limit 1),
    (select p.display_name from public.profiles p join public.conversation_participants cp on cp.user_id = p.id
      where cp.conversation_id = c.id and cp.user_id <> auth.uid() limit 1),
    (select p.avatar_url from public.profiles p join public.conversation_participants cp on cp.user_id = p.id
      where cp.conversation_id = c.id and cp.user_id <> auth.uid() limit 1),
    (select m.content from public.messages m where m.conversation_id = c.id order by m.created_at desc limit 1),
    (select m.created_at from public.messages m where m.conversation_id = c.id order by m.created_at desc limit 1),
    (select count(*) from public.messages m
      where m.conversation_id = c.id and m.sender_id <> auth.uid() and m.read_at is null
        and m.created_at > coalesce((select cp.last_read_at from public.conversation_participants cp
          where cp.conversation_id = c.id and cp.user_id = auth.uid()), '-infinity'::timestamptz))
  from public.conversations c
  where exists (select 1 from public.conversation_participants cp
    where cp.conversation_id = c.id and cp.user_id = auth.uid())
  order by (select m.created_at from public.messages m where m.conversation_id = c.id order by m.created_at desc limit 1) nulls first, c.updated_at desc;
$$;
