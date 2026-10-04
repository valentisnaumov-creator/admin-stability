-- v96: safe public chat identity lookup for authenticated staff
create or replace function public.get_chat_identities()
returns table(user_id uuid, nickname text, role text, avatar_url text, bio text)
language sql
security definer
set search_path=public
stable
as $$
  select r.user_id,
         coalesce(nullif(trim(r.nickname),''), split_part(coalesce(r.email,''),'@',1), 'Пользователь') as nickname,
         r.role,
         coalesce(p.avatar_url,'') as avatar_url,
         coalesce(p.bio,'') as bio
  from public.user_roles r
  left join public.user_profiles p on p.user_id=r.user_id
  where coalesce(r.is_blocked,false)=false
    and auth.uid() is not null;
$$;
grant execute on function public.get_chat_identities() to authenticated;
