-- v107: reliable invite roles + shared staff profiles

-- Apply the role from a valid invite atomically at signup.
create or replace function public.handle_new_user_role()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nick text := trim(coalesce(new.raw_user_meta_data->>'nickname',''));
  v_token text := trim(coalesce(new.raw_user_meta_data->>'invite_token',''));
  v_staff uuid;
  v_role text := 'trainee';
  v_invite_id bigint;
begin
  if v_token = '' then
    raise exception 'Регистрация доступна только по приглашению';
  end if;

  select id, role into v_invite_id, v_role
  from public.registration_invites
  where token = v_token and used_at is null and expires_at > now()
  for update;

  if v_invite_id is null then
    raise exception 'Приглашение недействительно, использовано или истекло';
  end if;
  if v_role not in ('creator','chief_admin','admin','trainee') then
    raise exception 'Некорректная роль приглашения';
  end if;

  if v_nick <> '' then
    select id into v_staff
    from public.staff
    where lower(name)=lower(v_nick) and dismissed_at is null
    limit 1;
  end if;

  insert into public.user_roles(user_id,email,nickname,staff_id,role,is_blocked)
  values(new.id,coalesce(new.email,''),v_nick,v_staff,v_role,false)
  on conflict(user_id) do update set
    email=excluded.email,
    nickname=excluded.nickname,
    staff_id=coalesce(excluded.staff_id,public.user_roles.staff_id),
    role=excluded.role,
    updated_at=now();

  update public.registration_invites
  set used_at=now(), used_by=new.id
  where id=v_invite_id;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created_role on auth.users;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created_role
after insert on auth.users
for each row execute procedure public.handle_new_user_role();

-- Shared profile fields. Email is intentionally not exposed.
alter table public.user_profiles
  add column if not exists display_status text not null default '',
  add column if not exists profile_banner text not null default '';

alter table public.user_profiles enable row level security;
drop policy if exists "profiles_authenticated_read" on public.user_profiles;
create policy "profiles_authenticated_read"
on public.user_profiles for select to authenticated
using (true);

drop policy if exists "profiles_self_insert" on public.user_profiles;
create policy "profiles_self_insert"
on public.user_profiles for insert to authenticated
with check (user_id=(select auth.uid()));

drop policy if exists "profiles_self_update" on public.user_profiles;
create policy "profiles_self_update"
on public.user_profiles for update to authenticated
using (user_id=(select auth.uid()))
with check (user_id=(select auth.uid()));

grant select,insert,update on public.user_profiles to authenticated;

-- One safe RPC for a complete profile card.
create or replace function public.get_staff_profile(p_user uuid)
returns table(
  user_id uuid,
  nickname text,
  account_role text,
  staff_id uuid,
  staff_role text,
  appointed_at date,
  yellow_cards integer,
  red_cards integer,
  avatar_url text,
  bio text,
  display_status text,
  profile_banner text,
  last_seen_at timestamptz,
  month_hours bigint,
  norm_days bigint,
  inactive_days bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    ur.user_id, ur.nickname, ur.role, ur.staff_id,
    s.role, s.appointed_at, coalesce(s.yellow_cards,0), coalesce(s.red_cards,0),
    up.avatar_url, up.bio, up.display_status, up.profile_banner,
    cp.last_seen_at,
    coalesce(sum(dm.norm_value) filter (
      where dm.status='norm'
        and dm.mark_date >= date_trunc('month',current_date)::date
        and dm.mark_date < (date_trunc('month',current_date)+interval '1 month')::date
    ),0)::bigint,
    count(*) filter (
      where dm.status='norm'
        and dm.mark_date >= date_trunc('month',current_date)::date
        and dm.mark_date < (date_trunc('month',current_date)+interval '1 month')::date
    )::bigint,
    count(*) filter (
      where dm.status='inactive'
        and dm.mark_date >= date_trunc('month',current_date)::date
        and dm.mark_date < (date_trunc('month',current_date)+interval '1 month')::date
    )::bigint
  from public.user_roles ur
  left join public.staff s on s.id=ur.staff_id
  left join public.user_profiles up on up.user_id=ur.user_id
  left join public.chat_presence cp on cp.user_id=ur.user_id
  left join public.daily_marks dm on dm.staff_id=ur.staff_id
  where ur.user_id=p_user
    and ur.is_blocked=false
    and auth.uid() is not null
  group by ur.user_id,ur.nickname,ur.role,ur.staff_id,s.role,s.appointed_at,
           s.yellow_cards,s.red_cards,up.avatar_url,up.bio,up.display_status,
           up.profile_banner,cp.last_seen_at;
$$;

revoke all on function public.get_staff_profile(uuid) from public;
grant execute on function public.get_staff_profile(uuid) to authenticated;
