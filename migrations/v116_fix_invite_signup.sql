-- v116: repair invite signup trigger
-- Makes invite registration resilient and removes the generic "Database error saving new user".

alter table public.registration_invites
  add column if not exists used_at timestamptz,
  add column if not exists used_by uuid references auth.users(id) on delete set null;

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
  v_role text;
  v_invite_id public.registration_invites.id%type;
begin
  if v_token = '' then
    raise exception using message = 'INVITE_REQUIRED';
  end if;

  select ri.id, ri.role
    into v_invite_id, v_role
  from public.registration_invites ri
  where ri.token = v_token
    and ri.used_at is null
    and ri.expires_at > now()
  for update;

  if v_invite_id is null then
    raise exception using message = 'INVITE_INVALID_OR_USED';
  end if;

  if v_role is null or v_role not in ('creator','chief_admin','admin','trainee') then
    v_role := 'trainee';
  end if;

  if v_nick <> '' then
    select s.id into v_staff
    from public.staff s
    where lower(s.name)=lower(v_nick)
      and s.dismissed_at is null
    limit 1;

    -- A nickname already owned by another account must not abort auth.users insert.
    -- Keep the new account usable; the nickname can be linked later by the creator.
    if exists (
      select 1 from public.user_roles ur
      where lower(ur.nickname)=lower(v_nick)
        and ur.nickname <> ''
        and ur.user_id <> new.id
    ) then
      v_nick := '';
      v_staff := null;
    end if;
  end if;

  insert into public.user_roles(user_id,email,nickname,staff_id,role,is_blocked)
  values(new.id,coalesce(new.email,''),v_nick,v_staff,v_role,false)
  on conflict(user_id) do update set
    email=excluded.email,
    nickname=case when excluded.nickname<>'' then excluded.nickname else public.user_roles.nickname end,
    staff_id=coalesce(excluded.staff_id,public.user_roles.staff_id),
    role=excluded.role,
    is_blocked=false,
    updated_at=now();

  update public.registration_invites
  set used_at=now(), used_by=new.id
  where id=v_invite_id;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created_role on auth.users;
create trigger on_auth_user_created_role
after insert on auth.users
for each row execute procedure public.handle_new_user_role();
