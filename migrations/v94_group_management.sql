-- v94: group roles, leave/delete and member limits
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
  v_role text;
  v_count int;
begin
  select member_role into v_role
  from public.chat_conversation_members
  where conversation_id=p_conversation and user_id=auth.uid();

  if v_role not in ('owner','admin') then raise exception 'Недостаточно прав'; end if;
  if not exists(select 1 from public.chat_conversations where id=p_conversation and kind='group') then raise exception 'Группа не найдена'; end if;

  if p_action='add' then
    select count(*) into v_count from public.chat_conversation_members where conversation_id=p_conversation;
    if v_count>=100 then raise exception 'В группе может быть не больше 100 участников'; end if;
    if exists(select 1 from public.user_roles where user_id=p_user and coalesce(is_blocked,false)=false) then
      insert into public.chat_conversation_members(conversation_id,user_id,member_role)
      values(p_conversation,p_user,'member')
      on conflict(conversation_id,user_id) do nothing;
    else
      raise exception 'Пользователь недоступен';
    end if;
  elsif p_action='remove' then
    if exists(select 1 from public.chat_conversation_members where conversation_id=p_conversation and user_id=p_user and member_role='owner') then
      raise exception 'Владельца группы удалить нельзя';
    end if;
    if v_role='admin' and exists(select 1 from public.chat_conversation_members where conversation_id=p_conversation and user_id=p_user and member_role='admin') then
      raise exception 'Администратор не может удалить другого администратора';
    end if;
    delete from public.chat_conversation_members where conversation_id=p_conversation and user_id=p_user;
  else
    raise exception 'Неизвестное действие';
  end if;
end $$;

create or replace function public.set_group_member_role(
  p_conversation uuid,
  p_user uuid,
  p_role text
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare v_me text; v_target text;
begin
  select member_role into v_me from public.chat_conversation_members
  where conversation_id=p_conversation and user_id=auth.uid();
  if v_me<>'owner' then raise exception 'Только владелец может менять администраторов'; end if;
  if p_role not in ('admin','member') then raise exception 'Недопустимая роль'; end if;
  select member_role into v_target from public.chat_conversation_members
  where conversation_id=p_conversation and user_id=p_user;
  if v_target is null then raise exception 'Пользователь не состоит в группе'; end if;
  if v_target='owner' then raise exception 'Нельзя изменить роль владельца'; end if;
  update public.chat_conversation_members set member_role=p_role
  where conversation_id=p_conversation and user_id=p_user;
end $$;

create or replace function public.leave_group_conversation(p_conversation uuid)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare v_role text;
begin
  select member_role into v_role from public.chat_conversation_members
  where conversation_id=p_conversation and user_id=auth.uid();
  if v_role is null then raise exception 'Вы не состоите в группе'; end if;
  if v_role='owner' then raise exception 'Владелец не может выйти из группы. Сначала удалите группу.'; end if;
  delete from public.chat_conversation_members
  where conversation_id=p_conversation and user_id=auth.uid();
end $$;

create or replace function public.delete_group_conversation(p_conversation uuid)
returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  if not exists(
    select 1 from public.chat_conversation_members
    where conversation_id=p_conversation and user_id=auth.uid() and member_role='owner'
  ) then raise exception 'Только владелец может удалить группу'; end if;
  if not exists(select 1 from public.chat_conversations where id=p_conversation and kind='group') then raise exception 'Группа не найдена'; end if;
  delete from public.chat_conversations where id=p_conversation;
end $$;

grant execute on function public.manage_group_member(uuid,uuid,text) to authenticated;
grant execute on function public.set_group_member_role(uuid,uuid,text) to authenticated;
grant execute on function public.leave_group_conversation(uuid) to authenticated;
grant execute on function public.delete_group_conversation(uuid) to authenticated;
