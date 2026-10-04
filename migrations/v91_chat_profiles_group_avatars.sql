-- v91: group avatars and editable chat identity
create or replace function public.update_group_profile(
  p_conversation uuid,
  p_title text default null,
  p_avatar_url text default null
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_role text;
  v_title text;
begin
  select member_role into v_role
  from public.chat_conversation_members
  where conversation_id=p_conversation and user_id=auth.uid();

  if v_role not in ('owner','admin') then
    raise exception 'Недостаточно прав';
  end if;

  if not exists(
    select 1 from public.chat_conversations
    where id=p_conversation and kind='group'
  ) then
    raise exception 'Группа не найдена';
  end if;

  if p_title is not null then
    v_title:=trim(p_title);
    if char_length(v_title) not between 2 and 64 then
      raise exception 'Название группы должно содержать от 2 до 64 символов';
    end if;
  end if;

  update public.chat_conversations
  set title=case when p_title is null then title else v_title end,
      avatar_url=case when p_avatar_url is null then avatar_url else p_avatar_url end
  where id=p_conversation;
end $$;

grant execute on function public.update_group_profile(uuid,text,text) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values(
  'group-avatars','group-avatars',true,3145728,
  array['image/jpeg','image/png','image/webp','image/gif']
)
on conflict(id) do update set
  public=true,
  file_size_limit=3145728,
  allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists "group avatars authenticated read" on storage.objects;
create policy "group avatars authenticated read"
on storage.objects for select to authenticated
using(bucket_id='group-avatars');

drop policy if exists "group avatars authenticated insert" on storage.objects;
create policy "group avatars authenticated insert"
on storage.objects for insert to authenticated
with check(bucket_id='group-avatars');

drop policy if exists "group avatars authenticated update" on storage.objects;
create policy "group avatars authenticated update"
on storage.objects for update to authenticated
using(bucket_id='group-avatars')
with check(bucket_id='group-avatars');

drop policy if exists "group avatars authenticated delete" on storage.objects;
create policy "group avatars authenticated delete"
on storage.objects for delete to authenticated
using(bucket_id='group-avatars');
