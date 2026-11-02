create table if not exists public.push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  firebase_installation_id text not null unique,
  platform text not null check (platform in ('android', 'iOS', 'web')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists push_tokens_user_id_idx
  on public.push_tokens(user_id);

alter table public.push_tokens enable row level security;

create policy "Users read their push tokens"
  on public.push_tokens for select to authenticated
  using (user_id = auth.uid());

create policy "Users register their push tokens"
  on public.push_tokens for insert to authenticated
  with check (user_id = auth.uid());

create policy "Users update their push tokens"
  on public.push_tokens for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy "Users remove their push tokens"
  on public.push_tokens for delete to authenticated
  using (user_id = auth.uid());

create extension if not exists pg_net with schema extensions;

create or replace function public.dispatch_message_push()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  endpoint text;
  webhook_secret text;
begin
  select decrypted_secret into endpoint
  from vault.decrypted_secrets where name = 'push_webhook_url' limit 1;

  select decrypted_secret into webhook_secret
  from vault.decrypted_secrets where name = 'push_webhook_secret' limit 1;

  if endpoint is null or webhook_secret is null then
    return new;
  end if;

  perform net.http_post(
    url := endpoint,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-bro-webhook-secret', webhook_secret
    ),
    body := jsonb_build_object(
      'type', tg_op,
      'table', tg_table_name,
      'schema', tg_table_schema,
      'record', to_jsonb(new),
      'old_record', null
    ),
    timeout_milliseconds := 5000
  );

  return new;
end;
$$;

drop trigger if exists dispatch_message_push on public.messages;
create trigger dispatch_message_push
  after insert on public.messages
  for each row execute function public.dispatch_message_push();
