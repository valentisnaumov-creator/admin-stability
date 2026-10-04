-- v100: trusted system inbox + automatic site events
create table if not exists public.system_messages(
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null default 'system',
  title text not null default 'Система',
  body text not null,
  link text not null default '',
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists system_messages_user_idx on public.system_messages(user_id,is_read,created_at desc);
alter table public.system_messages enable row level security;
drop policy if exists "system messages self read" on public.system_messages;
create policy "system messages self read" on public.system_messages for select to authenticated using(user_id=auth.uid());
drop policy if exists "system messages self update" on public.system_messages;
create policy "system messages self update" on public.system_messages for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());

create or replace function public.push_system_message(
  p_user uuid, p_kind text, p_title text, p_body text, p_link text default ''
) returns void language plpgsql security definer set search_path=public as $$
begin
  if p_user is null then return; end if;
  insert into public.system_messages(user_id,kind,title,body,link)
  values(p_user,coalesce(nullif(p_kind,''),'system'),left(coalesce(nullif(p_title,''),'Система'),120),left(coalesce(p_body,''),3000),coalesce(p_link,''));
  insert into public.site_notifications(user_id,kind,title,body,link)
  values(p_user,coalesce(nullif(p_kind,''),'system'),left(coalesce(nullif(p_title,''),'Система'),120),left(coalesce(p_body,''),2000),coalesce(p_link,''));
end $$;

revoke all on function public.push_system_message(uuid,text,text,text,text) from public, anon, authenticated;

create or replace function public.mark_system_messages_read()
returns void language sql security definer set search_path=public as $$
 update public.system_messages set is_read=true where user_id=auth.uid() and not is_read;
$$;
grant execute on function public.mark_system_messages_read() to authenticated;

-- group membership system events
create or replace function public.notify_group_membership()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_title text;
begin
 select coalesce(title,'Группа') into v_title from public.chat_conversations where id=coalesce(new.conversation_id,old.conversation_id);
 if tg_op='INSERT' and new.user_id<>auth.uid() then
   perform public.push_system_message(new.user_id,'group','Вас добавили в группу','Вы добавлены в группу «'||v_title||'».','chat:'||new.conversation_id::text);
 elsif tg_op='UPDATE' and new.member_role is distinct from old.member_role then
   perform public.push_system_message(new.user_id,'group_role','Права в группе изменены',
     case when new.member_role='admin' then 'Вы назначены администратором группы «'||v_title||'».'
          when old.member_role='admin' then 'С вас сняты права администратора группы «'||v_title||'».'
          else 'Ваша роль в группе «'||v_title||'» изменена.' end,
     'chat:'||new.conversation_id::text);
 elsif tg_op='DELETE' and old.user_id<>auth.uid() then
   perform public.push_system_message(old.user_id,'group','Вы удалены из группы','Вы были удалены из группы «'||v_title||'».','chat:general');
 end if;
 return coalesce(new,old);
end $$;
drop trigger if exists group_membership_system_notify on public.chat_conversation_members;
create trigger group_membership_system_notify after insert or update or delete on public.chat_conversation_members
for each row execute function public.notify_group_membership();

-- staff/account role changes
create or replace function public.notify_user_role_change()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_text text;
begin
 if tg_op='UPDATE' then
   if new.role is distinct from old.role then
     v_text:='Ваша роль на сайте изменена: '||coalesce(old.role,'—')||' → '||coalesce(new.role,'—')||'.';
     perform public.push_system_message(new.user_id,'role','Изменение роли',v_text,'');
   end if;
   if new.staff_id is distinct from old.staff_id then
     perform public.push_system_message(new.user_id,'staff','Привязка к составу изменена',
       case when new.staff_id is null then 'Ваш аккаунт отвязан от записи сотрудника.'
            else 'Ваш аккаунт привязан к записи сотрудника.' end,'');
   end if;
   if coalesce(new.is_blocked,false) is distinct from coalesce(old.is_blocked,false) and not new.is_blocked then
     perform public.push_system_message(new.user_id,'account','Доступ восстановлен','Ваш доступ к сайту восстановлен.','');
   end if;
 end if;
 return new;
end $$;
drop trigger if exists user_role_system_notify on public.user_roles;
create trigger user_role_system_notify after update on public.user_roles
for each row execute function public.notify_user_role_change();

do $$ begin
 alter publication supabase_realtime add table public.system_messages;
exception when duplicate_object then null;
end $$;
