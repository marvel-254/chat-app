-- Existing rows are ambiguous (some are plaintext, some reversibly encoded
-- with public inputs). Never rewrite or mark them as E2EE.
alter table public.messages add column content_format text not null default 'legacy_unversioned'
  check (content_format in ('legacy_unversioned','legacy_plaintext'));

-- The recipient update guard predates this column. Prevent recipients changing
-- format even when using a legal read-receipt UPDATE.
create function public.bro_guard_message_format() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.content_format is distinct from old.content_format
    and (auth.uid() is distinct from old.sender_id or new.content is not distinct from old.content) then
    raise exception using errcode = '42501', message = 'Message format cannot be changed independently';
  end if;
  return new;
end $$;
revoke all on function public.bro_guard_message_format() from public, anon, authenticated;
create trigger bro_guard_message_format before update on public.messages
  for each row execute function public.bro_guard_message_format();
