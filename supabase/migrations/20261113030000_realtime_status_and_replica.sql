-- Status feed uses supabase_flutter .stream() on public.statuses.
-- Chat messages filter realtime on conversation_id (not the PK), so replica
-- identity must be FULL or edits / deletes never reach the open chat.

do $$
begin
  alter publication supabase_realtime add table public.statuses;
exception
  when duplicate_object then null;
end $$;

alter table public.messages replica identity full;
alter table public.message_reactions replica identity full;
alter table public.statuses replica identity full;
alter table public.conversation_participants replica identity full;

drop policy if exists "Users leave conversations" on public.conversation_participants;
create policy "Users leave conversations" on public.conversation_participants
  for delete to authenticated
  using (user_id = auth.uid());
