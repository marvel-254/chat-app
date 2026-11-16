-- Status view tracking: who viewed which status, and when.
create table if not exists public.status_views (
  id uuid primary key default gen_random_uuid(),
  status_id uuid not null references public.statuses(id) on delete cascade,
  viewer_id uuid not null references auth.users(id) on delete cascade,
  viewed_at timestamptz not null default now(),
  unique (status_id, viewer_id)
);

create index if not exists status_views_status_id_idx on public.status_views (status_id);
create index if not exists status_views_viewer_id_idx on public.status_views (viewer_id);

alter table public.status_views enable row level security;

-- A signed-in user records their own views (upsert-safe via the unique pair).
create policy "Users record own status views"
  on public.status_views for insert to authenticated
  with check (viewer_id = auth.uid());

-- Owners see who viewed their statuses; viewers can re-read their own rows.
create policy "Owners read their status views"
  on public.status_views for select to authenticated
  using (
    viewer_id = auth.uid()
    or exists (
      select 1 from public.statuses s
      where s.id = status_id and s.user_id = auth.uid()
    )
  );

-- Live view counts for the owner while the viewer screen is open.
alter publication supabase_realtime add table public.status_views;
