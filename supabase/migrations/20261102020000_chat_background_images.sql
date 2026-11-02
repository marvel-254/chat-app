-- User-owned images for the personal chat canvas.
alter table public.profiles
  add column if not exists chat_background_image_path text;

alter table public.profiles
  drop constraint if exists profiles_chat_background_check;
alter table public.profiles
  add constraint profiles_chat_background_check
  check (chat_background in ('default', 'ocean', 'forest', 'plum', 'ember', 'custom'));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('chat-backgrounds', 'chat-backgrounds', false, 10485760,
  array['image/jpeg', 'image/png', 'image/webp', 'image/gif'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy "Users read own chat backgrounds" on storage.objects
  for select to authenticated using (
    bucket_id = 'chat-backgrounds'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
create policy "Users upload own chat backgrounds" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'chat-backgrounds'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
create policy "Users update own chat backgrounds" on storage.objects
  for update to authenticated using (
    bucket_id = 'chat-backgrounds'
    and (storage.foldername(name))[1] = auth.uid()::text
  ) with check (
    bucket_id = 'chat-backgrounds'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
