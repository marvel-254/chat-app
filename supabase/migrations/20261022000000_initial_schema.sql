-- enable extensions
create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";

-- profiles (public user info)
create table profiles (
  id uuid primary key references auth.users on delete cascade,
  username text unique not null,
  display_name text,
  avatar_url text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index on profiles(username);

-- conversations (1:1 chats)
create table conversations (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- conversation participants (join table)
create table conversation_participants (
  conversation_id uuid references conversations(id) on delete cascade,
  user_id uuid references profiles(id) on delete cascade,
  joined_at timestamptz default now(),
  last_read_at timestamptz,
  primary key (conversation_id, user_id)
);

-- messages
create table messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid references conversations(id) on delete cascade,
  sender_id uuid references profiles(id) on delete cascade,
  content text not null,
  created_at timestamptz default now(),
  read_at timestamptz
);
create index on messages(conversation_id, created_at desc);

-- RLS policies
alter table profiles enable row level security;
alter table conversations enable row level security;
alter table conversation_participants enable row level security;
alter table messages enable row level security;

-- profiles: users can read all, update own
create policy "Profiles readable by all" on profiles for select using (true);
create policy "Users update own profile" on profiles for update using (auth.uid() = id);

-- conversations: only participants can read
create policy "Participants read conversations" on conversations for select
  using (exists (
    select 1 from conversation_participants cp
    where cp.conversation_id = id and cp.user_id = auth.uid()
  ));

-- conversation_participants: users see own participations
create policy "Users see own participations" on conversation_participants for select
  using (user_id = auth.uid());
create policy "Users can join conversations" on conversation_participants for insert
  with check (user_id = auth.uid());

-- messages: participants can read, sender can insert/update own
create policy "Participants read messages" on messages for select
  using (exists (
    select 1 from conversation_participants cp
    where cp.conversation_id = messages.conversation_id and cp.user_id = auth.uid()
  ));
create policy "Sender inserts message" on messages for insert
  with check (sender_id = auth.uid());
create policy "Sender updates own message" on messages for update
  using (sender_id = auth.uid());

-- Realtime publication
alter publication supabase_realtime add table messages;
alter publication supabase_realtime add table conversation_participants;

-- Helper function to get or create DM
create or replace function get_or_create_dm(my_id uuid, other_id uuid)
returns uuid language plpgsql as $$
declare
  conv_id uuid;
begin
  -- Find existing 1:1 conversation between the two users
  select c.id into conv_id
  from conversations c
  join conversation_participants cp1 on cp1.conversation_id = c.id
  join conversation_participants cp2 on cp2.conversation_id = c.id
  where cp1.user_id = my_id and cp2.user_id = other_id
  and (select count(*) from conversation_participants where conversation_id = c.id) = 2
  limit 1;

  if conv_id is not null then
    return conv_id;
  end if;

  -- Create new conversation
  insert into conversations default values returning id into conv_id;
  insert into conversation_participants (conversation_id, user_id) values
    (conv_id, my_id),
    (conv_id, other_id);
  return conv_id;
end;
$$;