-- v86: group chats
alter table public.chat_conversations drop constraint if exists chat_conversations_kind_check;
alter table public.chat_conversations
  add constraint chat_conversations_kind_check check (kind in ('direct','group'));

alter table public.chat_conversations
  add column if not exists title text not null default '',
  add column if not exists avatar_url text not null default '';

alter table public.chat_conversation_members
  add column if not exists member_role text not null default 'member'
  check (member_role in ('owner','admin','member'));

create or replace function public.create_group_conversation(p_title text, p_members uuid[])
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_id uuid;
  v_title text := trim(coalesce(p_title,''));
  v_member uuid;
begin
  if auth.uid() is null then raise exception 'Необходимо войти'; end if;
  if char_length(v_title) not between 2 and 64 then
    raise exception 'Название группы должно содержать от 2 до 64 символов';
  end if;
  if coalesce(array_length(p_members,1),0) < 1 then
    raise exception 'Добавьте хотя бы одного участника';
  end if;
  if coalesce(array_length(p_members,1),0) > 99 then
    raise exception 'В группе может быть не более 100 участников';
  end if;

  insert into public.chat_conversations(kind,created_by,title)
  values('group',auth.uid(),v_title)
  returning id into v_id;

  insert into public.chat_conversation_members(conversation_id,user_id,member_role)
  values(v_id,auth.uid(),'owner');

  foreach v_member in array p_members loop
    if v_member <> auth.uid()
       and exists(select 1 from public.user_roles where user_id=v_member and coalesce(is_blocked,false)=false)
    then
      insert into public.chat_conversation_members(conversation_id,user_id,member_role)
      values(v_id,v_member,'member')
      on conflict(conversation_id,user_id) do nothing;
    end if;
  end loop;
  return v_id;
end $$;
grant execute on function public.create_group_conversation(text,uuid[]) to authenticated;

create or replace function public.manage_group_member(
  p_conversation uuid,
  p_user uuid,
  p_action text
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_my_role text;
  v_kind text;
begin
  select c.kind,m.member_role into v_kind,v_my_role
  from public.chat_conversations c
  join public.chat_conversation_members m on m.conversation_id=c.id and m.user_id=auth.uid()
  where c.id=p_conversation;

  if v_kind <> 'group' then raise exception 'Это не групповой чат'; end if;
  if v_my_role not in ('owner','admin') then raise exception 'Недостаточно прав'; end if;

  if p_action='add' then
    if not exists(select 1 from public.user_roles where user_id=p_user and coalesce(is_blocked,false)=false)
    then raise exception 'Пользователь недоступен'; end if;
    insert into public.chat_conversation_members(conversation_id,user_id)
    values(p_conversation,p_user)
    on conflict do nothing;
  elsif p_action='remove' then
    if exists(select 1 from public.chat_conversation_members where conversation_id=p_conversation and user_id=p_user and member_role='owner')
    then raise exception 'Нельзя удалить владельца группы'; end if;
    delete from public.chat_conversation_members where conversation_id=p_conversation and user_id=p_user;
  else
    raise exception 'Неизвестное действие';
  end if;
end $$;
grant execute on function public.manage_group_member(uuid,uuid,text) to authenticated;

create or replace function public.rename_group_conversation(p_conversation uuid,p_title text)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare v_role text;
begin
  select member_role into v_role from public.chat_conversation_members
  where conversation_id=p_conversation and user_id=auth.uid();
  if v_role not in ('owner','admin') then raise exception 'Недостаточно прав'; end if;
  if char_length(trim(coalesce(p_title,''))) not between 2 and 64 then raise exception 'Некорректное название'; end if;
  update public.chat_conversations set title=trim(p_title)
  where id=p_conversation and kind='group';
end $$;
grant execute on function public.rename_group_conversation(uuid,text) to authenticated;
