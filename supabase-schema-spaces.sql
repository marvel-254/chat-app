-- spaces schema
create table spaces (
  id uuid default gen_random_uuid() primary key,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  name text not null,
  description text,
  is_public boolean default true
);

create table space_members (
  space_id uuid references spaces(id) on delete cascade not null,
  user_id uuid references auth.users(id) on delete cascade not null,
  role text default 'member',
  primary key (space_id, user_id)
);

create table space_messages (
  id uuid default gen_random_uuid() primary key,
  space_id uuid references spaces(id) on delete cascade not null,
  user_id uuid references auth.users(id) not null,
  content text not null,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);
