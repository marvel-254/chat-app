-- last_message_at is computed in get_conversations_for_user(), but the
-- Flutter client was writing it onto conversations and PostgREST 400'd:
--   could not find "last_message_at" column of "conversations" in the schema cache
-- Add the column, keep it in sync from messages, and ping PostgREST.

alter table public.conversations
  add column if not exists last_message_at timestamptz;

create or replace function public.touch_conversation_on_message()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.conversations
     set updated_at = now(),
         last_message_at = new.created_at
   where id = new.conversation_id;
  return new;
end;
$$;

drop trigger if exists touch_conversation_on_message on public.messages;
create trigger touch_conversation_on_message
  after insert on public.messages
  for each row execute function public.touch_conversation_on_message();

notify pgrst, 'reload schema';
