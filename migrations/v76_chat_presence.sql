-- v76: presence and typing state for messenger
create table if not exists public.chat_presence (
  user_id uuid primary key references auth.users(id) on delete cascade,
  last_seen_at timestamptz not null default now(),
  typing_conversation_id uuid references public.chat_conversations(id) on delete set null,
  typing_until timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.chat_presence enable row level security;

drop policy if exists "presence_authenticated_read" on public.chat_presence;
create policy "presence_authenticated_read"
on public.chat_presence for select to authenticated
using (true);

drop policy if exists "presence_self_insert" on public.chat_presence;
create policy "presence_self_insert"
on public.chat_presence for insert to authenticated
with check (user_id = auth.uid());

drop policy if exists "presence_self_update" on public.chat_presence;
create policy "presence_self_update"
on public.chat_presence for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

create or replace function public.touch_chat_presence(
  p_conversation uuid default null,
  p_typing boolean default false
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Необходимо войти';
  end if;

  insert into public.chat_presence(
    user_id,last_seen_at,typing_conversation_id,typing_until,updated_at
  )
  values(
    auth.uid(),
    now(),
    case when p_typing then p_conversation else null end,
    case when p_typing then now() + interval '6 seconds' else null end,
    now()
  )
  on conflict (user_id) do update set
    last_seen_at = now(),
    typing_conversation_id = case when p_typing then p_conversation else null end,
    typing_until = case when p_typing then now() + interval '6 seconds' else null end,
    updated_at = now();
end;
$$;

grant execute on function public.touch_chat_presence(uuid, boolean) to authenticated;

do $$
begin
  begin
    alter publication supabase_realtime add table public.chat_presence;
  exception
    when duplicate_object then null;
  end;
end $$;
