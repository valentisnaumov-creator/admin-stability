-- v98: mentions, notification center and trusted system messages
create table if not exists public.site_notifications(
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null default 'system',
  title text not null default '',
  body text not null default '',
  link text not null default '',
  actor_user_id uuid references auth.users(id) on delete set null,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists site_notifications_user_idx on public.site_notifications(user_id,is_read,created_at desc);
alter table public.site_notifications enable row level security;
drop policy if exists "notifications self read" on public.site_notifications;
create policy "notifications self read" on public.site_notifications for select to authenticated using(user_id=auth.uid());
drop policy if exists "notifications self update" on public.site_notifications;
create policy "notifications self update" on public.site_notifications for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());

create table if not exists public.chat_mentions(
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  actor_user_id uuid not null references auth.users(id) on delete cascade,
  public_message_id bigint references public.chat_messages(id) on delete cascade,
  private_message_id bigint references public.private_messages(id) on delete cascade,
  conversation_id uuid references public.chat_conversations(id) on delete cascade,
  created_at timestamptz not null default now(),
  check ((public_message_id is not null)::int + (private_message_id is not null)::int = 1)
);
create unique index if not exists chat_mentions_public_unique on public.chat_mentions(user_id,public_message_id) where public_message_id is not null;
create unique index if not exists chat_mentions_private_unique on public.chat_mentions(user_id,private_message_id) where private_message_id is not null;
alter table public.chat_mentions enable row level security;
drop policy if exists "mentions self read" on public.chat_mentions;
create policy "mentions self read" on public.chat_mentions for select to authenticated using(user_id=auth.uid());

create or replace function public.mark_notification_read(p_id bigint)
returns void language sql security definer set search_path=public as $$
  update public.site_notifications set is_read=true where id=p_id and user_id=auth.uid();
$$;
create or replace function public.mark_all_notifications_read()
returns void language sql security definer set search_path=public as $$
  update public.site_notifications set is_read=true where user_id=auth.uid() and not is_read;
$$;

create or replace function public.notify_chat_mentions()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare r record; v_actor text; v_allowed boolean;
begin
  select coalesce(nullif(trim(nickname),''),split_part(coalesce(email,''),'@',1),'Пользователь')
  into v_actor from public.user_roles where user_id=new.user_id;

  for r in
    select ur.user_id, ur.nickname
    from public.user_roles ur
    where ur.user_id<>new.user_id
      and coalesce(ur.is_blocked,false)=false
      and nullif(trim(ur.nickname),'') is not null
      and position('@'||lower(trim(ur.nickname)) in lower(new.body))>0
  loop
    if tg_table_name='private_messages' then
      select public.is_conversation_member(new.conversation_id,r.user_id) into v_allowed;
    else
      v_allowed:=true;
    end if;
    if v_allowed then
      if tg_table_name='private_messages' then
        insert into public.chat_mentions(user_id,actor_user_id,private_message_id,conversation_id)
        values(r.user_id,new.user_id,new.id,new.conversation_id) on conflict do nothing;
      else
        insert into public.chat_mentions(user_id,actor_user_id,public_message_id)
        values(r.user_id,new.user_id,new.id) on conflict do nothing;
      end if;
      insert into public.site_notifications(user_id,kind,title,body,link,actor_user_id)
      values(r.user_id,'mention','Вас упомянули',coalesce(v_actor,'Пользователь')||' упомянул вас в сообщении',
        case when tg_table_name='private_messages' then 'chat:'||new.conversation_id::text else 'chat:general' end,new.user_id);
    end if;
  end loop;
  return new;
end $$;

drop trigger if exists chat_messages_mentions on public.chat_messages;
create trigger chat_messages_mentions after insert on public.chat_messages for each row execute function public.notify_chat_mentions();
drop trigger if exists private_messages_mentions on public.private_messages;
create trigger private_messages_mentions after insert on public.private_messages for each row execute function public.notify_chat_mentions();

create or replace function public.send_system_notification(
  p_user uuid,
  p_title text,
  p_body text,
  p_link text default ''
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare v_role text;
begin
  select role into v_role from public.user_roles where user_id=auth.uid();
  if v_role not in ('creator','chief_admin') then raise exception 'Недостаточно прав'; end if;
  if not exists(select 1 from public.user_roles where user_id=p_user and coalesce(is_blocked,false)=false) then raise exception 'Пользователь не найден'; end if;
  insert into public.site_notifications(user_id,kind,title,body,link,actor_user_id)
  values(p_user,'system',left(trim(p_title),120),left(trim(p_body),2000),coalesce(p_link,''),auth.uid());
end $$;

grant execute on function public.mark_notification_read(bigint) to authenticated;
grant execute on function public.mark_all_notifications_read() to authenticated;
grant execute on function public.send_system_notification(uuid,text,text,text) to authenticated;

do $$ begin
  alter publication supabase_realtime add table public.site_notifications;
exception when duplicate_object then null;
end $$;
