-- Allow the app to remove replaced photos and roll back a new upload if the
-- profile update fails. Status media and other users' files are excluded.
create policy "Users delete own profile avatars"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
    and array_length(storage.foldername(name), 1) = 1
    and storage.filename(name) ~ '^avatar(-[0-9a-f-]{36})?\.(jpg|jpeg|png|webp|gif|heic|heif)$'
  );
