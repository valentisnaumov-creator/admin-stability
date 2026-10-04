-- v81: apply invitation role atomically when auth user is created

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
  if v_nick <> '' then
    select id into v_staff
    from public.staff
    where lower(name)=lower(v_nick)
      and dismissed_at is null
    limit 1;
  end if;

  -- If signup came from an invite, lock and consume it during user creation.
  if v_token <> '' then
    select id, role
      into v_invite_id, v_role
    from public.registration_invites
    where token=v_token
      and used_at is null
      and expires_at > now()
    for update;

    if v_invite_id is null then
      raise exception 'Приглашение недействительно, уже использовано или истекло';
    end if;

    if v_role not in ('creator','chief_admin','admin','trainee') then
      raise exception 'Некорректная роль приглашения';
    end if;
  end if;

  insert into public.user_roles(user_id,email,nickname,staff_id,role)
  values(new.id,coalesce(new.email,''),v_nick,v_staff,v_role)
  on conflict (user_id) do update set
    email=excluded.email,
    nickname=case when public.user_roles.nickname='' then excluded.nickname else public.user_roles.nickname end,
    staff_id=coalesce(public.user_roles.staff_id,excluded.staff_id),
    role=case when v_token<>'' then excluded.role else public.user_roles.role end,
    updated_at=now();

  if v_invite_id is not null then
    update public.registration_invites
    set used_at=now(),
        used_by=new.id
    where id=v_invite_id;
  end if;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created_role on auth.users;
create trigger on_auth_user_created_role
after insert on auth.users
for each row execute procedure public.handle_new_user_role();
